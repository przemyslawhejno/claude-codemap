---
name: index-generator
description: Use when generating or updating project index content — invoked by /index command, index-planner, and index-writer agents as the shared format reference
---

# Index Generator — Format Reference

Shared format spec for `.claude/index/` files. Read this if you are the `index-planner`, `index-writer`, or the main session running `/index update`.

## Index Structure

```
.claude/index/
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

Override via `/index --compact` or `/index --detailed`.

## INDEX.md Format

```
# Project Index
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

## Skip List (Structure Scan)

Skip these during Glob/Grep:
- `node_modules`, `__pycache__`, `.git`, `dist`, `build`, `.claude/index/`
- `*.lock`, `*.min.*`, `*.map`
- Binaries and generated files

## Nested Projects

A directory is a nested sub-project if it contains any of:
- `.git/`
- `.claude/index/`
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

Applied by the `project-index` skill when Claude sees `pending.md`:

| Unique files in pending.md | Action                                                  |
|----------------------------|---------------------------------------------------------|
| ≤ 15                       | Main session updates affected topic files inline        |
| 16–50                      | Suggest `/index update` (Haiku writers, per topic)      |
| > 50                       | Suggest full `/index` rebuild                           |

## First Run in a Project

After generating `.claude/index/`, append to project's CLAUDE.md:

```
## Project Index
This project uses `.claude/index/` for fast file lookup.
Before searching for files, read `.claude/index/INDEX.md` to find relevant topic files.
If `.claude/index/pending.md` exists, update affected topic files before answering.
Run `/index update` when `.claude/index/pending.md` grows large; `/index` for full rebuild.
After completing a task, suggest `/compact` if context is heavy.
```
