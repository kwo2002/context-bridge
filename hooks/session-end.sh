#!/usr/bin/env bash
set -euo pipefail
HOOK_NAME=session-end
source "$(dirname "$0")/_common.sh"

read_input || exit 0
git_root=$(get_git_root) || git_root=$(pwd)

# 세션 종료 시 .context-capture/ 의 4 종 파일 cleanup. 없어도 무해.
rm -f "$(prompt_file_path        "$SESSION_ID" "$git_root")"
rm -f "$(offset_file_path        "$SESSION_ID" "$git_root")"
rm -f "$(delta_file_path         "$SESSION_ID" "$git_root")"
rm -f "$(pending_question_path   "$SESSION_ID" "$git_root")"
