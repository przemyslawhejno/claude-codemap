---
name: project-index
description: Use when .claude/index/INDEX.md exists in the project — guides file lookup through the index instead of exploratory searching, and suggests /compact after tasks
---

# Project Index

Fast file lookup via pre-built index. Cuts token usage 60-80% on navigation.

## How to Use

1. **Read `.claude/index/INDEX.md`** before Glob/Grep
2. **Match task** to 1-2 topics from INDEX.md
3. **Read only those topic files** — they list exact source file paths
4. **Go directly** to listed source files

## Pending Changes

If `.claude/index/pending.md` exists:
- Read it — files changed since last index update.
- Deduplicate paths.
- **≤ 15 unique files** → for each changed file, find its topic file (match paths inside topic files), re-read the source, update that section inline. Then delete `pending.md`.
- **16–50 unique files** → suggest `/index update` (Haiku writers regenerate affected topics, cheap and fast).
- **> 50 unique files** → suggest `/index` full rebuild.

## After Task

If context is heavy, suggest: `/compact`

## Do NOT

- Load all topic files at once
- Skip index for Glob/Grep searching
- Update topics outside pending.md flow — use `/index` for rebuild
