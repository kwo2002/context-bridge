#!/usr/bin/env bash
# Claude Code hook 공용 라이브러리. 실행 금지(source 전용).
# 사용: source "$(dirname "$0")/_common.sh"
# 호출 후 export 되는 변수: INPUT, SESSION_ID

# stdin JSON 읽어 INPUT 과 SESSION_ID export. SESSION_ID 비어있으면 1 반환.
read_input() {
  INPUT=$(cat)
  SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
  [[ -n "$SESSION_ID" ]] || return 1
  export INPUT SESSION_ID
}

# git root 출력. 없으면 비어있음.
get_git_root() {
  git rev-parse --show-toplevel 2>/dev/null
}

# .context-capture 디렉토리 생성.
ensure_context_dir() {
  local git_root="$1"
  mkdir -p "${git_root}/.context-capture"
}

# 파일 경로 헬퍼. 첫 인자 session_id, 둘째 git_root.
prompt_file_path()        { printf '%s' "$2/.context-capture/.claude-prompts-$1"; }
offset_file_path()        { printf '%s' "$2/.context-capture/.claude-offset-$1"; }
delta_file_path()         { printf '%s' "$2/.context-capture/.claude-conversation-delta-$1"; }
pending_question_path()   { printf '%s' "$2/.context-capture/.pending-question-$1"; }

# aiflare.yml 존재 여부.
has_aiflare_config() {
  local git_root="$1"
  [[ -f "${git_root}/aiflare.yml" ]]
}

# aiflare.yml 에서 api_key, endpoint 추출 후 export. 실패 시 1 반환.
read_aiflare_config() {
  local git_root="$1"
  local cfg="${git_root}/aiflare.yml"
  [[ -f "$cfg" ]] || return 1
  AIFLARE_API_KEY=$(grep -E '^api_key:' "$cfg" | awk '{print $2}' | tr -d '"'"'"'')
  AIFLARE_ENDPOINT=$(grep -E '^endpoint:' "$cfg" | awk '{print $2}' | tr -d '"'"'"'')
  [[ -n "$AIFLARE_API_KEY" ]] || return 1
  [[ -n "$AIFLARE_ENDPOINT" ]] || AIFLARE_ENDPOINT="https://api.aiflare.dev"
  export AIFLARE_API_KEY AIFLARE_ENDPOINT
}

# context-capture skill 디렉토리 존재 여부.
has_context_capture_skill() {
  local git_root="$1"
  [[ -d "${git_root}/.claude/skills/context-capture" ]]
}

# 로깅 (stderr). 형식: "[LEVEL] [hook=<name> session=<sid 8자>] message"
_log() {
  local level="$1"; shift
  local sid_short="${SESSION_ID:0:8}"
  printf '[%s] [hook=%s session=%s] %s\n' \
    "$level" "${HOOK_NAME:-unknown}" "$sid_short" "$*" >&2
}
log_info()  { _log INFO  "$@"; }
log_warn()  { _log WARN  "$@"; }
log_error() { _log ERROR "$@"; }
