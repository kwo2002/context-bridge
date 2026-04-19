#!/usr/bin/env bash
# AIFlare one-command install script
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
echo "Starting AIFlare installation..."
echo ""

# --- 1. Clone repository to a temporary location ---
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

CLONE_DIR="$TEMP_DIR/repo"
if ! git clone --depth 1 https://github.com/kwo2002/context-bridge.git "$CLONE_DIR" 2>/dev/null; then
  error "Failed to clone Skill repository. Please check your network connection."
  exit 1
fi
rm -rf "$CLONE_DIR/.git"

# --- 2. Install all skills ---
SKILLS_SOURCE="$CLONE_DIR/skills"
SKILLS_TARGET=".claude/skills"

if [[ ! -d "$SKILLS_SOURCE" ]]; then
  error "skills/ directory not found in cloned repository."
  exit 1
fi

mkdir -p "$SKILLS_TARGET"

for skill_path in "$SKILLS_SOURCE"/*/; do
  [[ -d "$skill_path" ]] || continue
  skill_name="$(basename "$skill_path")"
  target="$SKILLS_TARGET/$skill_name"
  if [[ -d "$target" ]]; then
    rm -rf "$target"
    warn "Replaced existing skill: $skill_name"
  fi
  cp -R "${skill_path%/}" "$SKILLS_TARGET/"
  info "Skill installed → $target"
done

CONTEXT_CAPTURE_DIR="$SKILLS_TARGET/context-capture"

# --- 3. Install MCP Server (shared across all skills) ---
MCP_SOURCE="$CLONE_DIR/mcp-server"
MCP_TARGET=".claude/mcp-server"

if [[ -d "$MCP_SOURCE" ]]; then
  rm -rf "$MCP_TARGET"
  cp -R "$MCP_SOURCE" "$MCP_TARGET"
  if command -v npm &>/dev/null; then
    (cd "$MCP_TARGET" && npm install --production --silent 2>/dev/null) || true
  fi
  info "MCP Server ready → $MCP_TARGET"
fi

# --- 4. Install settings.local.json (hooks) ---
SETTINGS_FILE=".claude/settings.local.json"
HOOKS_SOURCE="$CLONE_DIR/aiflare_settings.json"
MERGE_SCRIPT="$CLONE_DIR/scripts/merge-hooks.js"
REFERENCE_FILE=".claude/aiflare_settings.reference.json"

mkdir -p .claude

if [[ ! -f "$HOOKS_SOURCE" ]]; then
  warn "Hooks source file not found in repository: aiflare_settings.json"
elif [[ ! -f "$SETTINGS_FILE" ]]; then
  cp "$HOOKS_SOURCE" "$SETTINGS_FILE"
  info "Hooks config created → $SETTINGS_FILE"
elif command -v node &>/dev/null && [[ -f "$MERGE_SCRIPT" ]]; then
  cp "$SETTINGS_FILE" "$SETTINGS_FILE.bak"
  if node "$MERGE_SCRIPT" "$SETTINGS_FILE" "$HOOKS_SOURCE"; then
    info "Hooks merged → $SETTINGS_FILE (backup: $SETTINGS_FILE.bak)"
  else
    mv "$SETTINGS_FILE.bak" "$SETTINGS_FILE"
    warn "Hook merge failed. Original $SETTINGS_FILE restored."
    cp "$HOOKS_SOURCE" "$REFERENCE_FILE"
    echo "  Reference saved to $REFERENCE_FILE for manual merge."
  fi
else
  cp "$HOOKS_SOURCE" "$REFERENCE_FILE"
  warn "node not found. Cannot auto-merge hooks into existing $SETTINGS_FILE."
  echo "  Reference saved to $REFERENCE_FILE."
  echo "  Please merge its \"hooks\" section into $SETTINGS_FILE manually."
fi

# --- 5. Create .mcp.json ---
MCP_JSON=".mcp.json"
if [[ ! -f "$MCP_JSON" ]]; then
  printf '{\n  "mcpServers": {\n    "aiflare": {\n      "command": "node",\n      "args": [".claude/mcp-server/dist/index.js"]\n    }\n  }\n}\n' > "$MCP_JSON"
  info "MCP config created → $MCP_JSON"
else
  if ! grep -q 'aiflare' "$MCP_JSON" 2>/dev/null; then
    warn "Existing $MCP_JSON found. Please add aiflare MCP server manually."
  else
    info "aiflare already configured in $MCP_JSON"
  fi
fi

# --- 6. Update .gitignore ---
touch .gitignore

add_gitignore() {
  local pattern="$1"
  if ! grep -qx "$pattern" .gitignore 2>/dev/null; then
    echo "$pattern" >> .gitignore
    info "Added $pattern to .gitignore"
  else
    info "$pattern already in .gitignore"
  fi
}

add_gitignore 'aiflare.yml'
add_gitignore '.context-capture/'
add_gitignore '.claude/settings.local.json'

# --- 7. Install Git pre-push hook ---
PREPUSH_SOURCE="$CONTEXT_CAPTURE_DIR/scripts/pre-push"
HOOKS_TARGET_DIR=".git/hooks"

if [[ -f "$PREPUSH_SOURCE" ]]; then
  if [[ -f "$HOOKS_TARGET_DIR/pre-push" ]]; then
    warn "Existing $HOOKS_TARGET_DIR/pre-push found. Will not overwrite."
    echo "  Please merge manually:"
    echo "    cat $PREPUSH_SOURCE"
  else
    cp "$PREPUSH_SOURCE" "$HOOKS_TARGET_DIR/pre-push"
    chmod +x "$HOOKS_TARGET_DIR/pre-push"
    info "pre-push hook installed → $HOOKS_TARGET_DIR/pre-push"
  fi
else
  warn "pre-push hook script not found: $PREPUSH_SOURCE"
fi

# --- 8. Update CLAUDE.md ---
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
echo "  1. Go to AIFlare project settings → API Key Management and generate an API key"
echo "  2. Place the downloaded aiflare.yml in the project root"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
