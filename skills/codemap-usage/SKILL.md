---
name: codemap-usage
description: Use when .claude/codemap/INDEX.md exists in the project — guides file lookup through the index instead of exploratory searching, and suggests /compact after tasks
---

# Codemap

Fast file lookup via pre-built index. Cuts token usage 60-80% on navigation.

## Named-symbol lookup (check this first)

When the user's question names a specific symbol — a function, class, type, interface, enum, route, constant, component, or CLI command — read `.claude/codemap/symbols.md` first.

Examples that trigger symbol lookup:
- "where is `parseConfig` defined?"
- "show me the `AuthService` class"
- "which file handles `GET /users`?"
- "find the `<LoginForm>` component"

Steps:
1. Read `.claude/codemap/symbols.md` if it exists.
2. Grep for the symbol name. Lines look like `[kind] name → path:line`.
3. Open the referenced file and jump to the line.
4. Only fall back to `INDEX.md` → topic files if the symbol is absent from `symbols.md` or you need broader context (e.g. "how does auth *work*?" is conceptual, not a name lookup).

If `symbols.md` is missing, the index predates this feature or was not regenerated — suggest `/codemap` to the user.

## How to Use

For conceptual questions (no specific symbol named), use the INDEX → topic flow below. For name-based lookups, prefer `symbols.md` per the "Named-symbol lookup" section above.

1. **Read `.claude/codemap/INDEX.md`** before Glob/Grep
2. **Match task** to 1-2 topics from INDEX.md
3. **Read only those topic files** — they list exact source file paths
4. **Go directly** to listed source files

## Pending Changes

If `.claude/codemap/pending.md` exists:
- Read it — files changed since last index update.
- Deduplicate paths.
- **≤ 15 unique files** → for each changed file, find its topic file (match paths inside topic files), re-read the source, update that section inline. Then delete `pending.md`.
- **16–50 unique files** → suggest `/codemap update` (Haiku writers regenerate affected topics, cheap and fast).
- **> 50 unique files** → suggest `/codemap` full rebuild.

## After Task

If context is heavy, suggest: `/compact`

## Do NOT

- Load all topic files at once
- Skip index for Glob/Grep searching
- Update topics outside pending.md flow — use `/codemap` for rebuild
