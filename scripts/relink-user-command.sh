#!/usr/bin/env bash
# Re-point ~/.claude/commands/codemap.md at the latest installed plugin version.
#
# Usage: bash scripts/relink-user-command.sh
#
# Why: plugin commands are namespaced (e.g. /claude-codemap:codemap).
# Creating ~/.claude/commands/codemap.md as a symlink into the plugin cache
# exposes the command unqualified as /codemap. The plugin cache path includes
# the version, so this script re-points the symlink at the highest-versioned
# install. Run it after upgrading the plugin.
set -euo pipefail

cache_glob=~/.claude/plugins/cache/phejno-plugins/claude-codemap/*/
latest=$(ls -vd $cache_glob 2>/dev/null | tail -1)
if [[ -z "$latest" ]]; then
  echo "claude-codemap plugin not found under $cache_glob" >&2
  exit 1
fi

target="${latest}commands/codemap.md"
if [[ ! -f "$target" ]]; then
  echo "command file missing: $target" >&2
  exit 1
fi

mkdir -p ~/.claude/commands
ln -sfn "$target" ~/.claude/commands/codemap.md
echo "linked ~/.claude/commands/codemap.md → $target"
