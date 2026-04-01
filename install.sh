#!/usr/bin/env bash
# Context Bridge 원커맨드 설치 스크립트
# 사용법: curl -fsSL https://raw.githubusercontent.com/kwo2002/context-bridge/main/install.sh | bash

set -euo pipefail

# --- 색상 ---
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}!${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1" >&2; }

# --- git 설치 확인 ---
if ! command -v git &>/dev/null; then
  error "git이 설치되어 있지 않습니다. git을 먼저 설치해주세요."
  exit 1
fi

# --- git root 감지 ---
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
if [[ -z "$GIT_ROOT" ]]; then
  error "git 저장소가 아닙니다. 프로젝트 루트에서 실행해주세요."
  exit 1
fi

cd "$GIT_ROOT"
echo ""
echo "Context Bridge 설치를 시작합니다..."
echo ""

# --- 1. Skill 설치 ---
SKILL_DIR=".claude/skills/context-capture"
if [[ -d "$SKILL_DIR" ]]; then
  rm -rf "$SKILL_DIR"
  warn "기존 context-capture Skill을 제거하고 최신 버전으로 교체합니다."
fi

mkdir -p .claude/skills
if ! git clone --depth 1 https://github.com/kwo2002/context-bridge.git "$SKILL_DIR"; then
  error "Skill 저장소 클론에 실패했습니다. 네트워크 연결을 확인해주세요."
  rm -rf "$SKILL_DIR"
  exit 1
fi
rm -rf "$SKILL_DIR/.git"
rm -f "$SKILL_DIR/install.sh"

info "Skill 설치 완료 → $SKILL_DIR"

# --- 2. settings.json (hooks) 설치 ---
SETTINGS_FILE=".claude/settings.json"
HOOKS_SOURCE="$SKILL_DIR/settings.json"

if [[ ! -f "$SETTINGS_FILE" ]]; then
  mv "$HOOKS_SOURCE" "$SETTINGS_FILE"
  info "hooks 설정 생성 → $SETTINGS_FILE"
else
  warn "기존 $SETTINGS_FILE 이 있습니다. hooks를 수동으로 추가해주세요."
  echo ""
  echo "  $SETTINGS_FILE 을 열고, \"hooks\" 객체 안에 아래 3개 이벤트를 추가하세요."
  echo "  이미 \"hooks\" 키가 없다면 최상위에 \"hooks\": { ... } 를 만들어주세요."
  echo ""
  echo "  추가할 내용은 아래 파일에 있습니다:"
  echo "    cat $HOOKS_SOURCE"
  echo ""
  echo "  예시) 기존 settings.json 이 아래와 같다면:"
  echo "    {"
  echo "      \"permissions\": { ... },"
  echo "      \"hooks\": {"
  echo "        \"PreToolUse\": [ ... ]    ← 기존 hooks"
  echo "      }"
  echo "    }"
  echo ""
  echo "  \"hooks\" 안에 UserPromptSubmit, TaskCreated, TaskCompleted 를 추가하세요:"
  echo "    {"
  echo "      \"permissions\": { ... },"
  echo "      \"hooks\": {"
  echo "        \"PreToolUse\": [ ... ],   ← 기존 hooks"
  echo "        \"UserPromptSubmit\": [ ... ],"
  echo "        \"TaskCreated\": [ ... ],"
  echo "        \"TaskCompleted\": [ ... ]"
  echo "      }"
  echo "    }"
  rm -f "$HOOKS_SOURCE"
fi

# --- 3. .gitignore 업데이트 ---
touch .gitignore

if ! grep -qx 'context-bridge.yml' .gitignore 2>/dev/null; then
  echo 'context-bridge.yml' >> .gitignore
  info ".gitignore에 context-bridge.yml 추가"
else
  info ".gitignore에 context-bridge.yml 이미 존재"
fi

if ! grep -qx '.context-capture/' .gitignore 2>/dev/null; then
  echo '.context-capture/' >> .gitignore
  info ".gitignore에 .context-capture/ 추가"
else
  info ".gitignore에 .context-capture/ 이미 존재"
fi

# --- 4. CLAUDE.md 업데이트 ---
CLAUDE_MD="CLAUDE.md"
DIRECTIVE="git commit 후 반드시 context-capture skill을 실행하라."

if [[ ! -f "$CLAUDE_MD" ]]; then
  echo "$DIRECTIVE" > "$CLAUDE_MD"
  info "CLAUDE.md 생성 및 지시문 추가"
elif ! grep -qF "context-capture" "$CLAUDE_MD" 2>/dev/null; then
  echo "" >> "$CLAUDE_MD"
  echo "$DIRECTIVE" >> "$CLAUDE_MD"
  info "CLAUDE.md에 지시문 추가"
else
  info "CLAUDE.md에 context-capture 지시문 이미 존재"
fi

# --- 완료 안내 ---
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "설치 완료!"
echo ""
echo "  다음 단계:"
echo "  1. Context Bridge 프로젝트 설정 - API 키 관리 에서 API 키를 생성하세요"
echo "  2. 다운로드한 context-bridge.yml을 프로젝트 루트에 배치하세요"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
