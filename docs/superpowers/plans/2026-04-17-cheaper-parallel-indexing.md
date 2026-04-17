# Cheaper, Parallel Project Indexing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single-Sonnet `indexer` agent with a Sonnet `index-planner` that dispatches parallel Haiku `index-writer` agents, and add an explicit `/index update` subcommand.

**Architecture:** Two new agents — planner (Sonnet, cheap structural work) + writer (Haiku, cheap bulk work) — communicate via in-context plan. Writers run in parallel per topic. Index output format is unchanged; only the generation pipeline changes.

**Tech Stack:** Claude Code plugin (Markdown agent/skill/command files, JSON manifests, bash hook). No runtime code, no build step, no test framework — verification is structural (file shape checks) plus manual smoke tests.

**Spec:** `docs/superpowers/specs/2026-04-17-cheaper-parallel-indexing-design.md`

**Notes on test style:** This plugin has no unit test framework. "Test" steps in this plan are either (a) structural checks via `grep`/line counts, or (b) end-to-end smoke tests running `/index` against a fixture. Each task still follows write → verify → commit.

---

## Task 1: Bump plugin version

**Files:**
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 1: Update version from 0.1.0 to 0.2.0**

In `.claude-plugin/plugin.json`, change:

```json
"version": "0.1.0",
```

to:

```json
"version": "0.2.0",
```

- [ ] **Step 2: Verify**

Run: `grep '"version"' .claude-plugin/plugin.json`
Expected output: `  "version": "0.2.0",`

- [ ] **Step 3: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "chore: bump version to 0.2.0"
```

---

## Task 2: Update `index-generator` skill (format reference only)

**Rationale:** The planner and writer agents will both read this skill. Remove the full-rebuild process description (that logic now lives in the planner). Keep format specs. Update pending.md thresholds to match the new lifecycle.

**Files:**
- Modify: `skills/index-generator/SKILL.md`

- [ ] **Step 1: Rewrite the skill as a format reference**

Replace the entire file contents with:

```markdown
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
```

- [ ] **Step 2: Verify file structure**

Run: `grep -c '^## ' skills/index-generator/SKILL.md`
Expected: `10` (Index Structure, Detail Levels, INDEX.md Format, Topic File Format — Detailed, Topic File Format — Compact, Skip List, Nested Projects, Guardrails, Incremental Update Thresholds, First Run)

Run: `grep -c 'Full Rebuild' skills/index-generator/SKILL.md`
Expected: `0` (old process section is gone)

- [ ] **Step 3: Commit**

```bash
git add skills/index-generator/SKILL.md
git commit -m "refactor: convert index-generator skill to format reference only

Removes full-rebuild process (moving to planner agent). Keeps all
format specs shared between planner, writer, and main session.
Updates pending.md thresholds to match new /index update flow."
```

---

## Task 3: Create `index-writer` agent

**Rationale:** Writer is a leaf (no dispatching), so build it first. Runs on Haiku. One writer per topic, invoked with explicit inputs in the prompt.

**Files:**
- Create: `agents/index-writer.md`

- [ ] **Step 1: Create the agent file**

Write `agents/index-writer.md` with:

```markdown
---
name: index-writer
description: |
  Use this agent to generate a single topic file in .claude/index/. Dispatched by index-planner (during full rebuild) or by the main session (during /index update). Receives one topic's assignment in its prompt and writes exactly one .claude/index/{topic_name}.md file.

model: haiku
color: green
tools: ["Read", "Grep", "Write"]
---

You are a project index writer. Your job: given one topic and a file list, produce the topic file.

**REQUIRED:** Before starting, invoke the `index-generator` skill via the Skill tool — it contains the format spec you must follow.

## Input you receive (in your prompt)

- `topic_name` — e.g., `api-routes`, `data-models`
- `files` — either explicit paths or globs (resolve globs with Glob if needed — but prefer using Grep/Read on the explicit paths your caller provides)
- `detail_level` — `compact` or `detailed`
- `description` — one line summarizing what this topic covers (for the file header context)

## Your workflow

1. Resolve any globs in `files` to concrete paths.
2. Skip: binaries, lock files, `*.min.*`, `*.map`, files under skip-list directories (`node_modules`, `__pycache__`, `.git`, `dist`, `build`, `.claude/index/`).
3. For each remaining file:
   - Read just enough to identify signatures (classes, functions, endpoints, exports). Use Grep with targeted patterns before full Read when files are large.
   - Synthesize a 1-line description of what the file does.
4. Assemble the topic file per the format in the `index-generator` skill, matching the requested detail level.
5. Before writing, count lines in your planned output.
   - If **> 200 lines in detailed mode** → drop signatures, fall back to compact layout for this topic, retry once.
   - If **still > 200** → truncate the file list with a trailing line: `... (truncated, N files omitted)`.
6. Write to `.claude/index/{topic_name}.md`.
7. Report back to your caller:
   - `topic_file` — path written
   - `file_count` — how many files ended up in the topic
   - `skipped` — list of files skipped and why (if any)
   - `truncated` — true/false, and count if truncated
   - `fallback_to_compact` — true if detailed output exceeded size and fell back

## Guardrails

- Max 200 lines in your output file
- No code — only paths, names, signatures, 1-line descriptions
- Do not write INDEX.md — that is the planner's job
- Do not modify any file outside `.claude/index/{topic_name}.md`
- Do not dispatch other agents
```

- [ ] **Step 2: Verify structure**

Run: `head -20 agents/index-writer.md`
Expected: frontmatter shows `name: index-writer`, `model: haiku`, `tools: ["Read", "Grep", "Write"]`.

Run: `grep -c '^## ' agents/index-writer.md`
Expected: `3` (Input, Your workflow, Guardrails)

- [ ] **Step 3: Commit**

```bash
git add agents/index-writer.md
git commit -m "feat: add index-writer agent (haiku, per-topic worker)"
```

---

## Task 4: Create `index-planner` agent

**Rationale:** Planner runs Sonnet, decides topics, dispatches writers in parallel, then assembles INDEX.md.

**Files:**
- Create: `agents/index-planner.md`

- [ ] **Step 1: Create the agent file**

Write `agents/index-planner.md` with:

```markdown
---
name: index-planner
description: |
  Use this agent when generating or rebuilding a project index via /index command. Plans the topic split, dispatches parallel index-writer agents (one per topic), then assembles INDEX.md.

  <example>
  Context: User runs /index in a project
  user: "/index"
  assistant: "I'll use the index-planner agent to scan and dispatch writers."
  <commentary>
  Full rebuild — planner decides topics, writers (Haiku) generate in parallel, planner assembles INDEX.md.
  </commentary>
  </example>

model: sonnet
color: cyan
tools: ["Read", "Glob", "Grep", "Write", "Agent"]
---

You are the project index planner. Your job: scan the project, decide the topic split, dispatch writers in parallel, assemble INDEX.md.

**REQUIRED:** Before starting, invoke the `index-generator` skill via the Skill tool — it contains the format spec that you and your writers must follow.

## Your workflow

### Phase 1 — Structure scan (stay cheap on tokens)

1. Use Glob to map the directory tree. Skip: `node_modules`, `__pycache__`, `.git`, `dist`, `build`, `.claude/index/`, `*.lock`, `*.min.*`, `*.map`.
2. Detect nested sub-projects: a directory containing `.git/` or `.claude/index/`, or (`package.json` + `node_modules/`), or (`pyproject.toml` + `.venv/`). Record them for the `## Sub-projects` section. **Do not recurse into them.**
3. Count code files (exclude docs, configs, data). Auto-select detail level:
   - `< 50` → compact
   - `≥ 50` → detailed
   Respect any `--compact` or `--detailed` override from the task prompt.
4. Use Grep with targeted patterns (class/function/endpoint/export signatures) to sample file contents. Do not Read full source files here — leave that to writers.

### Phase 2 — Topic planning

5. Decide 5–10 cohesive topics. A topic is a group of files that relate to each other (API routes, data models, UI components, CLI tools, etc.). Name files descriptively (`api-routes.md`, `data-models.md`).
6. For each topic, hold in your context: `name`, `files` (explicit paths or globs), `description` (one-line).
7. **Small-project fallback:** if you cannot find at least 3 meaningful groups, create a single `overview.md` topic containing all code files. Log this decision in your final report.

### Phase 3 — Dispatch writers in parallel

8. For each topic, dispatch an `index-writer` agent using the Agent tool. **Send all writer calls in a single message with multiple Agent tool uses — this runs them concurrently.**
9. Each writer prompt must include:
   - `topic_name`
   - `files` (the explicit list or globs for that topic)
   - `detail_level` (the selected level)
   - `description`

Example writer dispatch prompt body:

```
Write .claude/index/api-routes.md for topic "api-routes".
Detail level: compact
Description: HTTP route handlers and request schemas.
Files:
- src/api/users.ts
- src/api/orders.ts
- src/api/auth.ts
Follow the format spec in the index-generator skill. Report back file_count, skipped, truncated, fallback_to_compact.
```

### Phase 4 — Assemble INDEX.md

10. After all writers report, write `.claude/index/INDEX.md` per the `index-generator` skill format:
    - Header: `Generated: YYYY-MM-DD`, `Level: compact|detailed`, `Files: N`
    - `## Structure` — top-level directories with short descriptions
    - `## Sub-projects` — pointers (omit section if none)
    - `## Topics` — list with `[topic-name](topic-name.md) — description`
11. If any writer failed, add a `⚠️` note next to the topic in the Topics list: `- [api-routes](api-routes.md) — …  ⚠️ generation failed — re-run /index`

### Phase 5 — Cleanup and report

12. If `.claude/index/pending.md` exists, delete it (index is now fresh).
13. Report summary to the parent session:
    - Topics created (count + list)
    - Total files indexed
    - Detail level used
    - Sub-projects detected (paths)
    - Writer failures (if any)
    - Fallback-to-flat (if triggered)

## Guardrails

- Max 10 topic files
- INDEX.md max 80 lines
- Do not write topic files yourself — always dispatch a writer
- Do not recurse into nested sub-projects
- Do not Read full source files in Phase 1 — use Grep with targeted patterns
```

- [ ] **Step 2: Verify structure**

Run: `head -25 agents/index-planner.md`
Expected: frontmatter shows `name: index-planner`, `model: sonnet`, `tools: ["Read", "Glob", "Grep", "Write", "Agent"]`.

Run: `grep -c '^### Phase' agents/index-planner.md`
Expected: `5`

- [ ] **Step 3: Commit**

```bash
git add agents/index-planner.md
git commit -m "feat: add index-planner agent (sonnet, dispatches parallel writers)"
```

---

## Task 5: Delete the old `indexer` agent

**Rationale:** Replaced by planner + writer.

**Files:**
- Delete: `agents/indexer.md`

- [ ] **Step 1: Delete the file**

```bash
git rm agents/indexer.md
```

- [ ] **Step 2: Verify**

Run: `ls agents/`
Expected output (order may vary):
```
index-planner.md
index-writer.md
```

Run: `grep -r 'indexer' commands/ skills/ agents/ 2>/dev/null`
Expected: no matches (no lingering references to the old agent name).

- [ ] **Step 3: Commit**

```bash
git commit -m "refactor: remove indexer agent (replaced by planner + writer)"
```

---

## Task 6: Rewrite `/index` command

**Rationale:** Command must dispatch the planner (not the old indexer) and add the `update` subcommand.

**Files:**
- Modify: `commands/index.md`

- [ ] **Step 1: Rewrite the file**

Replace the entire contents of `commands/index.md` with:

```markdown
---
description: "Generate, update, or inspect the project index for fast file lookup"
argument-hint: "[--compact|--detailed|status|update]"
---

Project index command. Manages `.claude/index/` for fast file navigation.

**Parse arguments from `$ARGUMENTS`:**

- **No arguments or `rebuild`**: Full rebuild (planner + parallel writers)
- **`--compact`**: Force compact detail level on rebuild
- **`--detailed`**: Force detailed detail level on rebuild
- **`status`**: Show index status, no changes
- **`update`**: Process `.claude/index/pending.md`, regenerate affected topic files

## If `status`

1. Check if `.claude/index/INDEX.md` exists.
2. If no: report "No index found. Run `/index` to generate."
3. If yes:
   - Read INDEX.md header (Generated date, Level, Files count).
   - Count topic files in `.claude/index/` (excluding `INDEX.md` and `pending.md`).
   - If `pending.md` exists, count unique lines in it.
4. Report status summary.

## If `update`

1. Check if `.claude/index/INDEX.md` exists. If not: report "No index to update. Run `/index` first."
2. Read `.claude/index/pending.md` if it exists. If missing or empty: report "Nothing pending. Index is up to date." and exit.
3. Deduplicate paths in `pending.md`.
4. If unique count > 50: report "Too many pending changes (N > 50). Run `/index` for full rebuild." and exit (do not auto-run).
5. Read INDEX.md to get the topic list (file names only).
6. For each topic, read `.claude/index/{topic}.md` and collect the list of source paths it currently references. Build `path → topic` map.
7. For each changed path in pending: match to its topic. Collect unmapped paths separately.
8. Dispatch one `index-writer` agent per affected topic, in parallel (single message, multiple Agent tool uses). Each writer prompt includes:
   - `topic_name`
   - `files` — the topic's **full current file list** (existing entries from the topic file, merged with any newly-changed paths mapped to this topic)
   - `detail_level` — read from INDEX.md header
   - `description` — read from INDEX.md topic line
9. After all writers complete, delete `.claude/index/pending.md`.
10. Report: topics updated (count + names), files processed, unmapped paths (if any, with a note that running full `/index` may be needed).

## If rebuild (default, or with `--compact` / `--detailed`)

1. Announce: "Indexing project..."
2. Invoke the `index-generator` skill via the Skill tool to load the format reference.
3. Dispatch the `index-planner` agent. Prompt template:

   ```
   Scan project at current working directory. Generate complete index in .claude/index/.
   Detail level override: [--compact | --detailed | auto]
   ```

   (Substitute the actual override based on `$ARGUMENTS`; use `auto` if neither flag is present.)
4. After the planner completes, check if this is the first run (no `## Project Index` section in `CLAUDE.md`).
5. **If first run:** append to `CLAUDE.md`:

   ```
   ## Project Index
   This project uses `.claude/index/` for fast file lookup.
   Before searching for files, read `.claude/index/INDEX.md` to find relevant topic files.
   If `.claude/index/pending.md` exists, update affected topic files before answering.
   Run `/index update` when `.claude/index/pending.md` grows large; `/index` for full rebuild.
   After completing a task, suggest `/compact` if context is heavy.
   ```

6. Report results from the planner's summary: topics created, files indexed, detail level, sub-projects, any failures.
7. Suggest commit: `git add .claude/index/ && git commit -m 'chore: update project index'`
   - If first run, also include `CLAUDE.md` in the commit suggestion.
```

- [ ] **Step 2: Verify structure**

Run: `grep -c '^## If' commands/index.md`
Expected: `3` (status, update, rebuild)

Run: `grep 'index-planner' commands/index.md`
Expected: a line referencing `index-planner` agent dispatch.

Run: `grep 'indexer' commands/index.md`
Expected: no output (old agent name not referenced).

- [ ] **Step 3: Commit**

```bash
git add commands/index.md
git commit -m "feat: rewrite /index command — dispatch planner, add update subcommand"
```

---

## Task 7: Update `project-index` skill thresholds

**Files:**
- Modify: `skills/project-index/SKILL.md`

- [ ] **Step 1: Rewrite the Pending Changes section**

Open `skills/project-index/SKILL.md`. Locate the `## Pending Changes` section.

Replace its current contents (the three bullets about pending.md behavior) with:

```markdown
## Pending Changes

If `.claude/index/pending.md` exists:
- Read it — files changed since last index update.
- Deduplicate paths.
- **≤ 15 unique files** → for each changed file, find its topic file (match paths inside topic files), re-read the source, update that section inline. Then delete `pending.md`.
- **16–50 unique files** → suggest `/index update` (Haiku writers regenerate affected topics, cheap and fast).
- **> 50 unique files** → suggest `/index` full rebuild.
```

- [ ] **Step 2: Verify**

Run: `grep -A2 '≤ 15' skills/project-index/SKILL.md`
Expected: mentions inline update.

Run: `grep '16–50' skills/project-index/SKILL.md`
Expected: one line mentioning `/index update`.

Run: `grep '> 50' skills/project-index/SKILL.md`
Expected: one line mentioning full rebuild.

- [ ] **Step 3: Commit**

```bash
git add skills/project-index/SKILL.md
git commit -m "feat: update project-index skill thresholds for /index update flow"
```

---

## Task 8: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Rewrite README with new lifecycle section**

Replace the entire contents of `README.md` with:

```markdown
# claude-project-index

Claude Code plugin that generates a compact project index for fast file lookup. Reduces token usage by 60-80% on navigation tasks.

## Install

```bash
claude plugins install /path/to/claude-project-index
```

## When to run what

| Command | When to use | What runs |
|---|---|---|
| `/index` | First time in a project, or when the index is stale/wrong | Full rebuild: Sonnet planner + N parallel Haiku writers (one per topic) |
| `/index update` | `pending.md` has many entries and you want a clean index without a full rebuild | Haiku writers only, for affected topics |
| `/index status` | Anytime — quick health check | Reads INDEX.md header + counts pending entries |
| `/index --compact` | Force compact detail level on rebuild | Same as `/index`, overrides auto-selection |
| `/index --detailed` | Force detailed detail level on rebuild | Same as `/index`, overrides auto-selection |

## How it works

1. `/index` scans your project and generates `.claude/index/` with:
   - `INDEX.md` — lightweight table of contents (~50-80 lines)
   - Topic files — grouped by domain (`api-routes.md`, `data-models.md`, etc.)
2. On each question, Claude reads `INDEX.md`, picks relevant topics, and goes directly to source files.
3. A PostToolUse hook tracks every file you edit to `.claude/index/pending.md`.
4. When Claude sees `pending.md`, it acts per the threshold:
   - **≤ 15 files** → updates affected topics inline in the current session
   - **16–50 files** → suggests `/index update` (Haiku-powered, runs in parallel)
   - **> 50 files** → suggests `/index` full rebuild
5. The index lives in your repo — commit it so it persists across sessions.

## Pipeline

Full rebuild (`/index`) uses a two-tier agent pipeline to keep costs down:

- **`index-planner`** (Sonnet) — scans structure, decides 5-10 topics, dispatches writers, assembles INDEX.md.
- **`index-writer`** (Haiku) — one per topic, reads the topic's files and writes the topic file. Run in parallel.

Incremental updates (`/index update`) skip the planner — Haiku writers regenerate only the affected topics.

## Detail levels

| Level | When | Content |
|---|---|---|
| compact | <50 code files | File paths + 1-line descriptions |
| detailed | 50+ code files | File paths + signatures + descriptions |

Auto-selected based on project size. Override with `--compact` or `--detailed`.

## Nested projects

Sub-projects (detected by `.git/`, `.claude/index/`, or language-specific markers) get a pointer in the parent's INDEX.md. Each project manages its own index independently.

## Plugin components

| Component | File | Purpose |
|---|---|---|
| Command | `commands/index.md` | `/index` slash command |
| Skill | `skills/project-index/SKILL.md` | How Claude uses the index |
| Skill | `skills/index-generator/SKILL.md` | Shared format reference |
| Agent | `agents/index-planner.md` | Sonnet planner — dispatches writers |
| Agent | `agents/index-writer.md` | Haiku per-topic worker |
| Hook | `hooks/track-changes.sh` | Tracks file edits to pending.md |
```

- [ ] **Step 2: Verify**

Run: `grep -c '^| ' README.md`
Expected: > 10 (several tables).

Run: `grep 'index-planner' README.md`
Expected: at least two lines.

Run: `grep 'indexer' README.md`
Expected: only the `.md` extension matches if any — no standalone "indexer" agent references. (Run `grep -w 'indexer' README.md` for the word-boundary check — expect no output.)

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: update README with new lifecycle and two-tier pipeline"
```

---

## Task 9: Smoke test — rebuild this plugin's own index

**Rationale:** This plugin itself is a small project — perfect fixture for the small-project fallback path (likely <3 meaningful topic groups, should fall back to `overview.md`). Validates end-to-end: planner dispatches writers, writers produce files, planner assembles INDEX.md, report comes back.

**Files:**
- Generates: `.claude/index/INDEX.md`, `.claude/index/*.md`

- [ ] **Step 1: Run /index in this project**

In a fresh Claude Code session at the plugin root:

```
/index
```

Expected flow:
1. Claude announces "Indexing project..."
2. `index-planner` (Sonnet) dispatches.
3. Planner reports: topics created, files indexed, detail level, any fallback-to-flat note.
4. One or more writer agents run in parallel (for a project this small, likely 1 topic → 1 writer, or fallback to `overview.md`).
5. `.claude/index/INDEX.md` appears with `## Topics` section.
6. Each topic listed exists as a `.md` file.

- [ ] **Step 2: Structural checks**

Run these verification commands:

```bash
test -f .claude/index/INDEX.md && echo "INDEX.md OK" || echo "MISSING"
wc -l .claude/index/INDEX.md    # expect ≤ 80
ls .claude/index/*.md | wc -l   # expect 2-3 (INDEX + 1-2 topics, since plugin is tiny)
for f in .claude/index/*.md; do wc -l "$f"; done  # each ≤ 200
grep '^## Topics' .claude/index/INDEX.md && echo "Topics section OK" || echo "MISSING Topics"
```

Expected: all checks pass. Size limits respected.

- [ ] **Step 3: Verify topic files resolve**

For each topic listed in `INDEX.md`'s `## Topics` section, confirm the referenced `.md` file exists:

```bash
grep -oE '\[([^]]+)\]\(([^)]+\.md)\)' .claude/index/INDEX.md | while read match; do
  file=$(echo "$match" | sed -E 's/.*\(([^)]+)\).*/\1/')
  test -f ".claude/index/$file" && echo "OK: $file" || echo "MISSING: $file"
done
```

Expected: every link resolves.

- [ ] **Step 4: CLAUDE.md first-run append**

Run: `grep '## Project Index' CLAUDE.md`

If `CLAUDE.md` already existed before `/index`, expect the section present. If this was a fresh project, the command should have created or appended it. Verify the section contains the new line: `Run /index update when ...`.

- [ ] **Step 5: Commit the generated index**

```bash
git add .claude/index/ CLAUDE.md 2>/dev/null
git status  # confirm which new/modified files are being committed
git commit -m "chore: bootstrap project index for claude-project-index plugin"
```

---

## Task 10: Smoke test — `/index update` flow

**Rationale:** Verify the update subcommand's end-to-end: hook populates pending.md → `/index update` reads it → dispatches writers → clears pending.md.

**Files:**
- Touches: any existing file in the plugin, to trigger the hook.

- [ ] **Step 1: Trigger the hook**

In the same Claude Code session, make a trivial edit to a single file (e.g., add then remove a blank line in `README.md`, or have Claude edit a comment). The PostToolUse hook will append the path to `.claude/index/pending.md`.

Run: `cat .claude/index/pending.md`
Expected: contains the path(s) of the edited file(s).

- [ ] **Step 2: Run /index update**

```
/index update
```

Expected flow:
1. Claude reads `pending.md`, reports count.
2. For the one (or few) changed files, matches to topic(s) by reading topic files.
3. Dispatches one `index-writer` per affected topic.
4. Clears `pending.md`.
5. Reports: topics updated, files processed.

- [ ] **Step 3: Verify**

```bash
test ! -f .claude/index/pending.md && echo "pending.md cleared OK" || echo "NOT CLEARED"
git diff .claude/index/   # show which topic file(s) were regenerated
```

Expected: `pending.md` is gone, one or more topic files show updates.

- [ ] **Step 4: Don't commit the test churn**

```bash
git checkout .claude/index/
```

This reverts the update-generated changes so the committed index stays clean.

---

## Task 11: Final commit / summary

- [ ] **Step 1: Verify full plugin state**

```bash
git log --oneline -15
git status  # expect: clean working tree
ls agents/  # expect: index-planner.md, index-writer.md
```

- [ ] **Step 2: Final review**

Open each of these in sequence and skim for leftover references to the old `indexer`:

- `commands/index.md`
- `skills/index-generator/SKILL.md`
- `skills/project-index/SKILL.md`
- `README.md`

Run: `grep -rw 'indexer' . --include='*.md' --exclude-dir='.git'`
Expected: no matches (word-boundary search for the standalone agent name).

---

## Self-Review Checklist (for the plan author — already performed)

1. **Spec coverage:** Every spec component (plugin version bump, new planner, new writer, old indexer removal, command rewrite with `update`, index-generator skill update, project-index skill update, README update) has a dedicated task. Cost estimate and migration sections are implicitly covered by the implementation. Verification section is covered by Tasks 9 and 10 (smoke tests).

2. **Placeholder scan:** No TBD/TODO/fill-in-later. All code content is shown in full. All verification commands have explicit expected output.

3. **Type consistency:** Agent names (`index-planner`, `index-writer`), command subcommands (`status`, `update`, `rebuild`), file paths (`.claude/index/INDEX.md`, `.claude/index/pending.md`, topic `.md` files), model tiers (`sonnet`, `haiku`), and detail levels (`compact`, `detailed`) are used consistently across all tasks.
