---
name: index-generator
description: Use when generating or updating project index content — invoked by /index command and during pending.md processing
---

# Index Generator

Generates compact project index files in `.claude/index/`.

## Index Structure

```
.claude/index/
├── INDEX.md      — TOC: project tree + topic list (~50-80 lines max)
├── pending.md    — change queue (hook-managed)
└── *.md          — topic files (5-10 files, ~100-200 lines each)
```

## Generation Process

### Full Rebuild (/index)

**Phase 1 — Structure scan:**
- Directory tree via Glob (skip: node_modules, __pycache__, .git, dist, build, .claude/index/, *.lock, *.min.*)
- Extract signatures: classes, functions, endpoints, components via Grep
- Note imports and dependencies

**Phase 2 — Categorization:**
- Choose 5-10 topics based on project structure (Claude decides)
- Name files descriptively: `api-routes.md`, `data-models.md`, `ui-components.md`
- Aim for cohesive grouping — files that relate to each other share a topic

**Phase 3 — Content generation:**
- Per topic file, list: file path + key signatures + 1-line description
- No code, no implementation details
- Use format matching detail level (see below)

### Detail Levels

Auto-select based on file count:

| Level | Threshold | Content |
|---|---|---|
| compact | <50 code files | `path — description` per file |
| detailed | 50+ code files | `path` + indented signatures + descriptions |

Override: `/index --compact` or `/index --detailed`

### INDEX.md Format

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

### Topic File Format (detailed)

```
# Topic Name

## Section
path/to/file.ext
  ClassName — what it does
  functionName(params) — what it does

path/to/other.ext
  endpoint METHOD /path — what it does
```

### Topic File Format (compact)

```
# Topic Name

path/to/file.ext — what this file does
path/to/other.ext — what this file does
```

## Incremental Update (pending.md)

1. Read `.claude/index/pending.md`
2. Deduplicate paths
3. If >15 unique files → suggest `/index` full rebuild
4. Otherwise: for each changed file, find its topic file → re-read source → update section
5. Delete pending.md after update

## Nested Projects

Skip directories containing any of: `.git/`, `.claude/index/`, `package.json` + `node_modules/`, `pyproject.toml` + `.venv/`

Add pointer in INDEX.md under `## Sub-projects` instead.

## Guardrails

- Max 10 topic files
- Max 200 lines per topic file
- INDEX.md max 80 lines
- No code in index — only paths, names, signatures, 1-line descriptions
- Skip binary files, generated files, lock files

## First Run in a Project

After generating `.claude/index/`, append to project's CLAUDE.md:

```
## Project Index
This project uses `.claude/index/` for fast file lookup.
Before searching for files, read `.claude/index/INDEX.md` to find relevant topic files.
If `.claude/index/pending.md` exists, update affected topic files before answering.
After completing a task, suggest `/compact` if context is heavy.
```
