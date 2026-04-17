# Flat Symbol Index — Design

**Date:** 2026-04-17
**Status:** Approved (pending plan)
**Builds on:** v0.2.0 (cheaper parallel indexing)

## Goal

Give Claude a one-read answer to "where is symbol X defined?" by adding a flat `symbols.md` file that maps every named declaration to its source path.

## Motivation

Today, a question like "where is `parseConfig` defined?" forces Claude through INDEX.md → the likely topic file → the source file (3 reads minimum, more if the first topic guess is wrong). A flat symbol index collapses that to one read for any named-symbol question, which is the most common navigation query.

## Scope

**In:** all named declarations — functions, methods, classes, types, interfaces, enums, HTTP routes, top-level constants, React components, CLI commands.

**Out:** local variables, inline lambdas, test cases, documentation anchors.

## File format

Location: `.claude/index/symbols.md`

```
# Symbols
Generated: YYYY-MM-DD
Count: N

[class] AuthService → src/auth/service.ts:12
[cmd]   index → commands/index.md:1
[component] LoginForm → web/src/LoginForm.tsx:8
[const] MAX_RETRIES → src/config.ts:5
[enum]  Status → src/types.ts:20
[fn]    parseConfig → src/config.ts:42
[route] GET /users → src/api/users.ts:15
[type]  User → src/types.ts:3
```

**Line format:** `[kind] name → path:line`

**Kinds:** `fn`, `class`, `type`, `enum`, `route`, `const`, `component`, `cmd`.

**Ordering:** alphabetical by `name`, case-insensitive.

**Size cap:** 3000 symbols. Past cap, truncate and append:

```
> N symbols omitted — fall back to Grep for uncommon names
```

## Generation

### `/index` full rebuild

1. **`index-writer`** (Haiku, unchanged model) — while reading its topic's files to extract signatures for the topic file, it also emits a `symbols:` block in its report back to the planner. Format:

   ```
   symbols:
     [fn] parseConfig → src/config.ts:42
     [class] AuthService → src/auth/service.ts:12
     ...
   ```

   Each writer only emits symbols for files it was assigned. No extra file reads — the writer already reads these files for topic-file generation.

2. **`index-planner`** — new Phase 4b after writers complete and before INDEX.md assembly:
   - Concatenate all writer `symbols:` blocks
   - Deduplicate (same `name + path:line` line)
   - Sort alphabetically by name (case-insensitive)
   - Apply 3000-symbol cap
   - Write `.claude/index/symbols.md`

3. **`index-planner`** — INDEX.md Topics section includes:
   ```
   - [symbols](symbols.md) — flat name → path lookup for all defined symbols
   ```

### `/index update` incremental

The `update` command already dispatches writers per affected topic. After writers complete:

1. Read existing `.claude/index/symbols.md` into memory
2. Remove lines whose `path` matches any file in the affected topics' file lists
3. Merge in fresh `symbols:` blocks from the re-run writers
4. Re-sort, re-apply cap, rewrite `symbols.md`

Symbols from unaffected topics stay untouched.

### Inline pending updates (≤15 files)

Not handled in MVP. The next `/index update` or full rebuild picks up the drift. Keeping the `project-index` skill simple outweighs the staleness cost for <=15 file changes.

## Usage (project-index skill)

New rule added to `skills/project-index/SKILL.md`:

> **Named-symbol lookup:** When the user's question names a specific symbol — function, class, type, route, constant, component, or CLI command — read `.claude/index/symbols.md` first. Jump directly to the referenced file. Only fall back to the INDEX → topic flow if the symbol is absent or you need broader context.

Existing INDEX → topic flow for conceptual questions stays unchanged.

## Files to modify

| File | Change |
|---|---|
| `agents/index-writer.md` | Add `symbols:` block to output format; document kind tags |
| `agents/index-planner.md` | Add Phase 4b (compose `symbols.md`); add symbols line to Topics |
| `commands/index.md` | Update flow: partial `symbols.md` rewrite after writers complete |
| `skills/index-generator/SKILL.md` | New section: `symbols.md` format spec |
| `skills/project-index/SKILL.md` | Add named-symbol lookup rule |
| `README.md` | One line under structure + mention in usage table |

No new agents. No new commands. No new hooks.

## Guardrails

- Max 3000 symbols in `symbols.md`
- Symbols file is a view — never authoritative; source files are truth
- Writer emits only symbols for files it was assigned (no duplication across writers)
- Dedupe on exact `[kind] name → path:line` match (handles rare edge case where two writers see the same file)

## Non-goals

- Fuzzy matching / search ranking — alphabetical order is enough
- Cross-references (who calls `foo`) — Grep handles this
- Type signatures in `symbols.md` — those belong in topic files
- Per-first-letter shards — single file until it's proven insufficient
- Symbol kind beyond the 8 listed — keep the tag set stable and small

## Open questions

None blocking. Route extraction heuristics (what counts as a `[route]` across frameworks) will be addressed in the implementation plan; writer prompts get framework-aware grep patterns.

## Expected impact

- Named-symbol navigation: 3+ reads → 1 read
- `symbols.md` size at 1500 symbols ≈ 90KB, at cap 3000 ≈ 180KB — one read is still cheaper than the multi-read flow it replaces
- Generation cost: near-zero delta (writers already read the files)
