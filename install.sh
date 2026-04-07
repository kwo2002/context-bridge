#!/usr/bin/env bash
# Context Bridge one-command install script
# Usage: curl -fsSL https://raw.githubusercontent.com/kwo2002/context-bridge/main/install.sh | bash

set -euo pipefail

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}!${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1" >&2; }

# --- Check git installation ---
if ! command -v git &>/dev/null; then
  error "git is not installed. Please install git first."
  exit 1
fi

# --- Detect git root ---
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
if [[ -z "$GIT_ROOT" ]]; then
  error "Not a git repository. Please run from the project root."
  exit 1
fi

cd "$GIT_ROOT"
echo ""
echo "Starting Context Bridge installation..."
echo ""

# --- 1. Install Skill ---
SKILL_DIR=".claude/skills/context-capture"
if [[ -d "$SKILL_DIR" ]]; then
  rm -rf "$SKILL_DIR"
  warn "Removing existing context-capture Skill and replacing with latest version."
fi

mkdir -p .claude/skills
if ! git clone --depth 1 https://github.com/kwo2002/context-bridge.git "$SKILL_DIR"; then
  error "Failed to clone Skill repository. Please check your network connection."
  rm -rf "$SKILL_DIR"
  exit 1
fi
rm -rf "$SKILL_DIR/.git"
rm -f "$SKILL_DIR/install.sh"

info "Skill installed → $SKILL_DIR"

# --- 2. Install settings.local.json (hooks) ---
SETTINGS_FILE=".claude/settings.local.json"
HOOKS_SOURCE="$SKILL_DIR/settings.json"

if [[ ! -f "$SETTINGS_FILE" ]]; then
  mv "$HOOKS_SOURCE" "$SETTINGS_FILE"
  info "Hooks config created → $SETTINGS_FILE (hooks + mcpServers)"
else
  warn "Existing $SETTINGS_FILE found. Please add hooks manually."
  echo ""
  echo "  Open $SETTINGS_FILE and add the following events inside the \"hooks\" object."
  echo "  If there is no \"hooks\" key, create one at the top level: \"hooks\": { ... }"
  echo ""
  echo "  The content to add is in this file:"
  echo "    cat $HOOKS_SOURCE"
  echo ""
  echo "  Example) If your existing settings.json looks like this:"
  echo "    {"
  echo "      \"permissions\": { ... },"
  echo "      \"hooks\": {"
  echo "        \"PreToolUse\": [ ... ]    ← existing hooks"
  echo "      }"
  echo "    }"
  echo ""
  echo "  Add all 7 events inside \"hooks\":"
  echo "    {"
  echo "      \"permissions\": { ... },"
  echo "      \"hooks\": {"
  echo "        \"PreToolUse\": [ ... ],       ← existing hooks"
  echo "        \"SessionStart\": [ ... ],     ← work session creation"
  echo "        \"PostToolUse\": [ ... ],      ← post-commit capture reminder + conversation log"
  echo "        \"UserPromptSubmit\": [ ... ], ← user prompt logging"
  echo "        \"Stop\": [ ... ],             ← assistant response logging"
  echo "        \"SessionEnd\": [ ... ],       ← work session cleanup"
  echo "        \"TaskCreated\": [ ... ],      ← task creation tracking"
  echo "        \"TaskCompleted\": [ ... ]     ← task completion tracking"
  echo "      }"
  echo "    }"
  rm -f "$HOOKS_SOURCE"
fi

# --- 3. Update .gitignore ---
touch .gitignore

if ! grep -qx 'context-bridge.yml' .gitignore 2>/dev/null; then
  echo 'context-bridge.yml' >> .gitignore
  info "Added context-bridge.yml to .gitignore"
else
  info "context-bridge.yml already in .gitignore"
fi

if ! grep -qx '.context-capture/' .gitignore 2>/dev/null; then
  echo '.context-capture/' >> .gitignore
  info "Added .context-capture/ to .gitignore"
else
  info ".context-capture/ already in .gitignore"
fi

if ! grep -qx '.claude/settings.local.json' .gitignore 2>/dev/null; then
  echo '.claude/settings.local.json' >> .gitignore
  info "Added .claude/settings.local.json to .gitignore"
else
  info ".claude/settings.local.json already in .gitignore"
fi

# --- 4. Install Git hook ---
SKILL_PREPUSH="$SKILL_DIR/scripts/pre-push"
HOOKS_TARGET_DIR=".git/hooks"

if [[ -f "$SKILL_PREPUSH" ]]; then
  if [[ -f "$HOOKS_TARGET_DIR/pre-push" ]]; then
    warn "Existing $HOOKS_TARGET_DIR/pre-push found. Will not overwrite."
    echo "  Please merge manually:"
    echo "    cat $SKILL_PREPUSH"
  else
    cp "$SKILL_PREPUSH" "$HOOKS_TARGET_DIR/pre-push"
    chmod +x "$HOOKS_TARGET_DIR/pre-push"
    info "pre-push hook installed → $HOOKS_TARGET_DIR/pre-push"
  fi
else
  warn "pre-push hook script not found: $SKILL_PREPUSH"
fi

# --- 5. Update CLAUDE.md ---
CLAUDE_MD="CLAUDE.md"
DIRECTIVE="After git commit, you must always run the context-capture skill."

if [[ ! -f "$CLAUDE_MD" ]]; then
  echo "$DIRECTIVE" > "$CLAUDE_MD"
  info "CLAUDE.md created with directive"
elif ! grep -qF "context-capture" "$CLAUDE_MD" 2>/dev/null; then
  echo "" >> "$CLAUDE_MD"
  echo "$DIRECTIVE" >> "$CLAUDE_MD"
  info "Directive added to CLAUDE.md"
else
  info "context-capture directive already exists in CLAUDE.md"
fi

# --- Done ---
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "Installation complete!"
echo ""
echo "  Next steps:"
echo "  1. Go to Context Bridge project settings → API Key Management and generate an API key"
echo "  2. Place the downloaded context-bridge.yml in the project root"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
