---
name: codemap-format
description: Use when generating or updating codemap content — invoked by /codemap command, codemap-planner, and codemap-writer agents as the shared format reference
---

# Codemap — Format Reference

Shared format spec for `.claude/codemap/` files. Read this if you are the `codemap-planner`, `codemap-writer`, or the main session running `/codemap update`.

## Codemap Structure

```
.claude/codemap/
├── INDEX.md      — TOC: project tree + topic list (~50-80 lines max)
├── pending.md    — change queue (hook-managed)
└── *.md          — topic files (5-10 files, ~100-200 lines each)
```

## Detail Levels

Auto-selected based on code file count:

| Level    | Threshold       | Content                                         |
|----------|-----------------|-------------------------------------------------|
| compact  | <50 code files  | `path — description` per file                   |
| detailed | 50+ code files  | `path` + indented signatures + descriptions     |

Override via `/codemap --compact` or `/codemap --detailed`.

## INDEX.md Format

```
# Codemap
Generated: YYYY-MM-DD
Level: compact|detailed
Files: N

## Structure
dir/       — short description
dir/       — short description

## Sub-projects
- subdir/ — description (has own index)

## Topics
- [topic-name](topic-name.md) — what this topic covers (key terms for matching)
```

## Topic File Format — Detailed

```
# Topic Name

## Section
path/to/file.ext
  ClassName — what it does
  functionName(params) — what it does

path/to/other.ext
  endpoint METHOD /path — what it does
```

## Topic File Format — Compact

```
# Topic Name

path/to/file.ext — what this file does
path/to/other.ext — what this file does
```

## symbols.md Format

Flat, alphabetical-by-name symbol index for one-read "where is X?" lookups. Produced once per rebuild and kept in lockstep with topic files on `/codemap update`.

```
# Symbols
Generated: YYYY-MM-DD
Count: N

[class] AuthService → src/auth/service.ts:12
[cmd]   codemap → commands/codemap.md:1
[component] LoginForm → web/src/LoginForm.tsx:8
[const] MAX_RETRIES → src/config.ts:5
[enum]  Status → src/types.ts:20
[fn]    parseConfig → src/config.ts:42
[route] GET /users → src/api/users.ts:15
[type]  User → src/types.ts:3
```

**Line format:** `[kind] name → path:line`

**Kinds (fixed set of 8):**
- `fn` — functions, methods
- `class` — classes
- `type` — types, interfaces, type aliases
- `enum` — enums
- `route` — HTTP routes / endpoints (`METHOD /path`)
- `const` — top-level constants
- `component` — React / Vue / Svelte components
- `cmd` — CLI commands / slash commands

**Ordering:** alphabetical by `name`, case-insensitive.

**Size cap:** 3000 symbols. Past cap, truncate and append a final line:

```
> N symbols omitted — fall back to Grep for uncommon names
```

**Scope:** named declarations only. Skip local variables, inline lambdas, test cases, doc anchors.

**Usage:** the main session reads `symbols.md` first when the user's question names a specific symbol; falls back to INDEX → topic flow for conceptual questions.

## Skip List (Structure Scan)

Skip these during Glob/Grep:
- `node_modules`, `__pycache__`, `.git`, `dist`, `build`, `.claude/codemap/`
- `*.lock`, `*.min.*`, `*.map`
- Binaries and generated files

## Nested Projects

A directory is a nested sub-project if it contains any of:
- `.git/`
- `.claude/codemap/`
- `package.json` + `node_modules/`
- `pyproject.toml` + `.venv/`

Add a pointer in INDEX.md under `## Sub-projects`. Do not recurse into it.

## Guardrails

- Max 10 topic files
- Max 200 lines per topic file
- INDEX.md max 80 lines
- No code in index — only paths, names, signatures, 1-line descriptions
- Skip binary files, generated files, lock files

## Incremental Update Thresholds (pending.md)

Applied by the `codemap-usage` skill when Claude sees `pending.md`:

| Unique files in pending.md | Action                                                  |
|----------------------------|---------------------------------------------------------|
| ≤ 15                       | Main session updates affected topic files inline        |
| 16–50                      | Suggest `/codemap update` (Haiku writers, per topic)      |
| > 50                       | Suggest full `/codemap` rebuild                           |

## First Run in a Project

After generating `.claude/codemap/`, append to project's CLAUDE.md:

```
## Codemap
This project uses `.claude/codemap/` for fast file lookup.
Before searching for files, read `.claude/codemap/INDEX.md` to find relevant topic files.
If `.claude/codemap/pending.md` exists, update affected topic files before answering.
Run `/codemap update` when `.claude/codemap/pending.md` grows large; `/codemap` for full rebuild.
After completing a task, suggest `/compact` if context is heavy.
```
