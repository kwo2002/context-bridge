#!/usr/bin/env bash
# Context Bridge Capture Script
# 서브에이전트나 훅에서 직접 실행 가능한 독립 스크립트
#
# 사용법:
#   capture.sh --title "제목" --intent "의도" --commit-hash "abc123" --agent-type "CLAUDE_CODE" \
#     --user-request-id "UUID" --user-request-prompt "사용자 요청" \
#     --changed-files "file1.kt,file2.kt" --tag "FEATURE" \
#     [--alternatives "대안"] [--diff-summary "변경 요약"]
#
# --user-request-id 및 --user-request-prompt 가 생략되면
# 프로젝트 루트의 .claude-user-prompt-*.txt 파일에서 자동으로 읽습니다.
#
# 환경변수로도 전달 가능:
#   CB_TITLE, CB_INTENT, CB_COMMIT_HASH, CB_AGENT_TYPE, CB_USER_REQUEST_ID,
#   CB_USER_REQUEST_PROMPT, CB_CHANGED_FILES, CB_TAG, CB_ALTERNATIVES, CB_DIFF_SUMMARY

set -euo pipefail

# --- 인자 파싱 ---
TITLE="${CB_TITLE:-}"
INTENT="${CB_INTENT:-}"
COMMIT_HASH="${CB_COMMIT_HASH:-}"
AGENT_TYPE="${CB_AGENT_TYPE:-CLAUDE_CODE}"
USER_REQUEST_ID="${CB_USER_REQUEST_ID:-}"
USER_REQUEST_PROMPT="${CB_USER_REQUEST_PROMPT:-}"
CHANGED_FILES="${CB_CHANGED_FILES:-}"
TAG="${CB_TAG:-}"
ALTERNATIVES="${CB_ALTERNATIVES:-}"
DIFF_SUMMARY="${CB_DIFF_SUMMARY:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)        TITLE="$2";        shift 2 ;;
    --intent)       INTENT="$2";       shift 2 ;;
    --commit-hash)  COMMIT_HASH="$2";  shift 2 ;;
    --agent-type)   AGENT_TYPE="$2";   shift 2 ;;
    --user-request-id) USER_REQUEST_ID="$2"; shift 2 ;;
    --user-request-prompt) USER_REQUEST_PROMPT="$2"; shift 2 ;;
    --changed-files) CHANGED_FILES="$2"; shift 2 ;;
    --tag)          TAG="$2";          shift 2 ;;
    --alternatives) ALTERNATIVES="$2"; shift 2 ;;
    --diff-summary) DIFF_SUMMARY="$2"; shift 2 ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 1 ;;
  esac
done

# --- 설정 파일 탐색 (git root 기준) ---
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
if [[ -z "$GIT_ROOT" ]]; then
  echo "Context Bridge 캡처 건너뜀: git 저장소가 아닙니다."
  exit 0
fi

CONFIG_FILE="${GIT_ROOT}/context-bridge.yml"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Context Bridge 캡처 건너뜀: context-bridge.yml 파일이 없습니다."
  exit 0
fi

# --- 설정값 추출 (yq 없이 grep/sed로 처리) ---
API_KEY="$(grep -E '^\s*api_key\s*:' "$CONFIG_FILE" | sed 's/^[^:]*:\s*//' | sed 's/^["'"'"']//' | sed 's/["'"'"']$//' | tr -d '[:space:]')"
ENDPOINT="$(grep -E '^\s*endpoint\s*:' "$CONFIG_FILE" | sed 's/^[^:]*:\s*//' | sed 's/^["'"'"']//' | sed 's/["'"'"']$//' | tr -d '[:space:]')"

if [[ -z "$API_KEY" || -z "$ENDPOINT" ]]; then
  echo "Context Bridge 캡처 건너뜀: context-bridge.yml에 api_key 또는 endpoint가 누락되었습니다."
  exit 0
fi

# --- Claude PID로 프롬프트 파일 읽기 ---
if [[ -z "$USER_REQUEST_ID" || -z "$USER_REQUEST_PROMPT" ]]; then
  # capture.sh → bash → claude 프로세스 체인에서 Claude PID 추출
  CLAUDE_PID="$(ps -o ppid= -p $PPID 2>/dev/null | tr -d ' ')"
  PROMPT_FILE="${GIT_ROOT}/.context-capture/.claude-user-prompt-${CLAUDE_PID}.txt"

  # PID 매핑 실패 시 fallback: 가장 최근 파일
  if [[ -z "$CLAUDE_PID" || ! -f "$PROMPT_FILE" ]]; then
    PROMPT_FILE="$(ls -t "${GIT_ROOT}/.context-capture"/.claude-user-prompt-*.txt 2>/dev/null | head -1)"
  fi

  if [[ -n "$PROMPT_FILE" && -f "$PROMPT_FILE" ]]; then
    if [[ -z "$USER_REQUEST_ID" ]]; then
      USER_REQUEST_ID="$(head -1 "$PROMPT_FILE")"
    fi
    if [[ -z "$USER_REQUEST_PROMPT" ]]; then
      USER_REQUEST_PROMPT="$(tail -n +2 "$PROMPT_FILE")"
    fi
  fi
fi

# --- 필수 필드 검증 ---
if [[ -z "$TITLE" || -z "$INTENT" || -z "$COMMIT_HASH" || -z "$USER_REQUEST_ID" || -z "$USER_REQUEST_PROMPT" || -z "$CHANGED_FILES" || -z "$TAG" ]]; then
  echo "오류: --title, --intent, --commit-hash, --user-request-id, --user-request-prompt, --changed-files, --tag 는 필수입니다." >&2
  exit 1
fi

# --- 임시 파일 (PID 포함으로 동시 실행 안전) ---
PAYLOAD_FILE="/tmp/cb-capture-payload-$$.json"
trap 'rm -f "$PAYLOAD_FILE"' EXIT

# --- JSON 이스케이프 함수 ---
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  echo "$s"
}

# --- changedFiles를 JSON 배열로 변환 (쉼표 구분 문자열 → ["a","b"]) ---
build_changed_files_json() {
  local input="$1"
  local result="["
  local first=true
  IFS=',' read -ra FILES <<< "$input"
  for file in "${FILES[@]}"; do
    file="$(echo "$file" | xargs)"  # trim whitespace
    if [[ -n "$file" ]]; then
      if [[ "$first" == true ]]; then
        first=false
      else
        result+=","
      fi
      result+="\"$(json_escape "$file")\""
    fi
  done
  result+="]"
  echo "$result"
}

CHANGED_FILES_JSON="$(build_changed_files_json "$CHANGED_FILES")"

# --- 페이로드 생성 ---
cat > "$PAYLOAD_FILE" << PAYLOAD_EOF
{
  "title": "$(json_escape "$TITLE")",
  "intent": "$(json_escape "$INTENT")",
  "alternatives": "$(json_escape "$ALTERNATIVES")",
  "diffSummary": "$(json_escape "$DIFF_SUMMARY")",
  "commitHash": "$(json_escape "$COMMIT_HASH")",
  "agentType": "$(json_escape "$AGENT_TYPE")",
  "userRequestId": "$(json_escape "$USER_REQUEST_ID")",
  "userRequestPrompt": "$(json_escape "$USER_REQUEST_PROMPT")",
  "changedFiles": ${CHANGED_FILES_JSON},
  "tag": "$(json_escape "$TAG")"
}
PAYLOAD_EOF

# --- API 호출 ---
RESPONSE="$(curl -s -w "\n%{http_code}" \
  -X POST "${ENDPOINT}/api/v1/captures" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: ${API_KEY}" \
  -d @"$PAYLOAD_FILE" 2>&1)"

HTTP_CODE="$(echo "$RESPONSE" | tail -1)"
BODY="$(echo "$RESPONSE" | sed '$d')"

# --- 결과 처리 ---
case "$HTTP_CODE" in
  201) echo "Context Bridge 캡처 완료: ${TITLE}"
       # 캡처 완료 마커 — 다음 프롬프트에서 Hook이 새 UUID로 파일을 초기화하도록 신호
       if [[ -n "${CLAUDE_PID:-}" ]]; then
         mkdir -p "${GIT_ROOT}/.context-capture"
         touch "${GIT_ROOT}/.context-capture/.claude-captured-${CLAUDE_PID}"
       fi
       ;;
  400) echo "Context Bridge 캡처 실패: 요청 데이터 오류 — ${BODY}" ;;
  401) echo "Context Bridge 캡처 실패: API Key가 유효하지 않습니다." ;;
  404) echo "Context Bridge 캡처 실패: API Key에 연결된 프로젝트를 찾을 수 없습니다." ;;
  429) echo "Context Bridge 캡처 실패: 요청 한도 초과. 잠시 후 다시 시도해주세요." ;;
  *)   echo "Context Bridge 캡처 실패: HTTP ${HTTP_CODE} — 서버 오류. 나중에 수동으로 재시도해주세요." ;;
esac
