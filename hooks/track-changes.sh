#!/bin/bash
# PostToolUse hook: append changed file path to .claude/codemap/pending.md
# Input: JSON via stdin with tool_input.file_path
# Only acts if .claude/codemap/ exists (project has been indexed)

set -euo pipefail

CODEMAP_DIR=".claude/codemap"

# Skip if project not indexed
if [ ! -d "$CODEMAP_DIR" ]; then
  exit 0
fi

# Read hook input from stdin
input=$(cat)

# Extract file path from tool input
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

if [ -z "$file_path" ]; then
  exit 0
fi

# Make path relative to project root if absolute
if [[ "$file_path" == /* ]]; then
  project_dir=$(pwd)
  file_path="${file_path#"$project_dir"/}"
fi

# Skip changes to .claude/codemap/ itself (avoid self-referencing)
if [[ "$file_path" == .claude/codemap/* ]]; then
  exit 0
fi

# Append to pending.md (deduplicated on next read, not here — keep hook fast)
echo "$file_path" >> "$CODEMAP_DIR/pending.md"

exit 0
