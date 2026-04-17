# Cheaper, Parallel Project Indexing — Design

**Date:** 2026-04-17
**Status:** Approved for planning
**Plugin:** `claude-project-index` (v0.1.0 → v0.2.0)

## Problem

The current `/index` full rebuild runs a single `indexer` agent on `sonnet`. Sonnet is used for all three phases — scanning, categorization, and generation — even though scanning and generation are mechanical and do not need its judgment. This makes rebuilds unnecessarily expensive.

Secondary: users find the current command surface unclear. Only `/index` and `/index status` exist; updates happen "automatically" via a hook + skill combo that is not visible in the command list. Users do not know when to trigger an update manually.

## Goals

1. Cut token cost of `/index` rebuilds by routing expensive work to cheaper models.
2. Reduce wall-clock rebuild time by parallelizing topic generation.
3. Make the update lifecycle visible through an explicit `/index update` subcommand.
4. Preserve the existing `.claude/index/` output format so current indexes remain valid.

## Non-Goals

- Changing the index file format (INDEX.md layout, topic file layout).
- Reworking the PostToolUse hook.
- Rewriting the lookup flow used by the `project-index` skill. Lookup improvements are deferred to a later design.
- Unit test infrastructure. This plugin ships with manual/structural verification only.

## Architecture

The single `indexer` agent is replaced by two agents running at different tiers:

```
/index command (main session)
     │
     ▼
┌──────────────────────┐
│  index-planner       │  model: sonnet
│  - scans structure   │  tools: Glob, Grep, Read, Write, Agent
│  - decides topics    │  small token footprint
│  - dispatches writers│
│  - assembles INDEX   │
└──────────┬───────────┘
           │ in-context plan (not a file):
           │   detail_level, topics[{name, files, description}]
           ▼
┌──────────────────────────────────────────────────┐
│  index-writer × N  (one per topic, in parallel)  │  model: haiku
│  tools: Read, Grep, Write                        │
│  input: {topic_name, files, detail_level, desc}  │
│  output: .claude/index/{topic_name}.md           │
└──────────┬───────────────────────────────────────┘
           │
           ▼
      index-planner
      writes INDEX.md, clears pending.md,
      reports summary to main session
```

**Why this split works:**
- Sonnet touches only directory structure and light signatures — the token-cheap part of the work.
- Haiku does all source-file reading and topic-file writing — the token-heavy part, ~3.5× cheaper per token.
- Writers run in parallel, so wall-clock time is `max(topic_time)` rather than `sum(topic_time)`.
- The plan lives in the planner's context, not a file. No intermediate artifact to clean up.

## Components

### 1. `/index` command — modified

File: `commands/index.md`

Arguments unchanged: `--compact`, `--detailed`, `status`, no-args rebuild.

**New subcommand:** `update` — process `pending.md` without a full rebuild.

Behavior:
- `status` — unchanged.
- No args or `rebuild` — dispatch `index-planner` agent with task description + detail override.
- `--compact` / `--detailed` — same, passed through to planner.
- `update` — read `pending.md`, group paths by topic (using INDEX.md's topic mapping), dispatch `index-writer` agents in parallel for each affected topic, clear `pending.md`, report.

First-run CLAUDE.md append stays in the command (unchanged), with one line added:
`Run /index update when .claude/index/pending.md grows large; /index for full rebuild.`

### 2. `index-planner` agent — new

File: `agents/index-planner.md`

- **Model:** `sonnet`
- **Tools:** `Glob`, `Grep`, `Read`, `Write`, `Agent`
- **Workflow:**
  1. Read the `index-generator` skill for format specs.
  2. Scan project structure with Glob (skip: `node_modules`, `__pycache__`, `.git`, `dist`, `build`, `.claude/index/`, `*.lock`, `*.min.*`, `*.map`).
  3. Detect sub-projects (directory contains `.git/` or `.claude/index/`) — add pointers in INDEX.md, do not recurse.
  4. Auto-select detail level: <50 code files → compact, 50+ → detailed. Respect `--compact` / `--detailed` override.
  5. Decide 5-10 cohesive topics with file lists + 1-line descriptions. For very small projects (<3 meaningful groups), fall back to one `overview.md` topic containing all files.
  6. Dispatch one `index-writer` agent per topic, in parallel (single message, multiple Agent tool calls). Each writer receives `{topic_name, files, detail_level, description}` in its prompt.
  7. After all writers report done, write `INDEX.md` with project tree, sub-project pointers, and the topic list.
  8. Clear `pending.md` if it exists.
  9. Report summary to main session: topic count, file count, detail level, any sub-projects detected, any writer failures.

### 3. `index-writer` agent — new

File: `agents/index-writer.md`

- **Model:** `haiku`
- **Tools:** `Read`, `Grep`, `Write`
- **Workflow:**
  1. Read the `index-generator` skill for format specs.
  2. Resolve globs in the input file list to actual paths.
  3. For each file: extract signatures via Grep/Read, synthesize a 1-line description.
  4. Write `.claude/index/{topic_name}.md` in the format matching detail level.
  5. Before Write, check output size. If >200 lines in detailed mode, drop signatures (fall back to compact layout for this topic) and retry once. If still >200, truncate with a trailing `... (truncated, N files omitted)` line.
  6. Skip binaries, lock files, generated files, and anything matching the planner's skip list.
  7. Report back: topic file path written, file count, any files skipped or truncated.

### 4. `indexer` agent — removed

File: `agents/indexer.md` — delete. Replaced by planner + writer.

### 5. `index-generator` skill — updated

File: `skills/index-generator/SKILL.md`

- **Keep:** format specifications (INDEX.md layout, topic file layout, detail levels, guardrails, nested project rules).
- **Remove:** the full-rebuild process description (that logic now lives in the planner agent).
- **Keep:** incremental update section, but rewrite to reflect the new split:
  - Small batches (≤15 unique files) — main session updates affected topic files inline (unchanged).
  - Larger batches — suggest `/index update`; if >50, suggest full `/index`.
- Both planner and writer read this skill, so it becomes a shared format reference.

### 6. `project-index` skill — minor update

File: `skills/project-index/SKILL.md`

Update the "Pending Changes" section thresholds and suggestions:
- ≤15 files → inline update in main session.
- 16–50 files → suggest `/index update`.
- >50 files → suggest full `/index`.

### 7. Hook — unchanged

File: `hooks/track-changes.sh` — no changes.

### 8. README — updated

File: `README.md`

Add a "When to run what" section with this table:

| Command | When to use | What runs |
|---|---|---|
| `/index` | First time in a project, or when existing index is stale/wrong | Full rebuild: planner + N parallel writers |
| `/index update` | `pending.md` has many entries, you want a clean index without a full rebuild | Writers only, for affected topics |
| `/index status` | Anytime — quick health check | Reads INDEX.md header + counts pending entries |

Also document the automatic update flow (hook → pending.md → skill-triggered inline update for small batches, suggestion to run `/index update` for larger batches).

## Data Flow

### Full rebuild (`/index`)

1. User runs `/index` in main session.
2. Main session reads the command definition, dispatches `index-planner` with task + detail override.
3. Planner scans, decides topics, holds plan in context.
4. Planner dispatches N writers in parallel (single message, multiple Agent tool calls).
5. Each writer reads its assigned files, writes its topic file, reports back.
6. Planner receives all writer results, writes INDEX.md.
7. Planner clears `pending.md` (if exists), reports summary to main session.
8. Main session reports to user, suggests commit.

### Incremental update (`/index update`)

1. User runs `/index update` in main session.
2. Main session reads `pending.md`, deduplicates paths.
3. If empty → "nothing pending", exit.
4. If >50 files → recommend full `/index`, exit.
5. Main session reads `INDEX.md` to get the topic list, then reads each topic file to collect its current file paths. Each changed path is matched to the topic whose file already contains it. Paths not found in any topic are collected as "unmapped".
6. Main session dispatches one `index-writer` per affected topic, in parallel. Each writer is given the topic's **full current file list** (existing entries from the topic file, plus any newly-changed paths that map to this topic) — not just the changed subset — so the topic file is regenerated cleanly.
7. Main session clears `pending.md`, reports topics updated, files processed, and any unmapped paths.

No planner needed — the partitioning already exists across the topic files. Unmapped paths (e.g., a brand-new file in a directory no topic covers) signal the user may need a full `/index`; they are reported but not auto-handled.

### Inline update (skill-triggered, small batches)

Unchanged from today. The `project-index` skill runs in the main session when INDEX.md exists and `pending.md` is small.

## Error Handling

| Failure | Behavior |
|---|---|
| One writer fails | Planner writes INDEX.md anyway with a `⚠️ topic-name.md: generation failed` note. Other topics remain valid. User re-runs `/index` to retry. |
| Writer output exceeds 200 lines in detailed mode | Writer drops signatures, retries in compact layout once. If still over, truncates with `... (truncated, N files omitted)`. |
| Planner cannot identify ≥3 meaningful groups | Falls back to a single `overview.md` topic. Logs "Project too small for topic split — generating flat index". |
| Hook failure | Unchanged — `exit 0` on any issue, fire-and-forget. |
| `pending.md` references a deleted file | Writer's Read fails gracefully; file is dropped from the topic. |
| `/index update` can't match a changed file to any topic | File is listed in the report as "unmapped"; user can run full `/index` if it matters. |

## Verification

No unit tests. Verification is manual + structural:

1. **Structural checks** after any rebuild, performed by the planner before reporting success:
   - `INDEX.md` exists with `## Structure` and `## Topics` sections.
   - Every topic listed in INDEX.md has a corresponding `.md` file in `.claude/index/`.
   - No topic file exceeds 200 lines; INDEX.md ≤ 80 lines.
2. **Test repos** before committing plugin changes:
   - This plugin itself (small, ~15 files) — verifies fallback-to-flat path.
   - A medium JS/TS repo (~100 files) — verifies normal path + parallel dispatch.
   - A repo with a nested sub-project — verifies sub-project pointer path.
3. **Optional smoke script** (`scripts/smoke-test.sh`) — runs `/index` against a fixture, diffs output tree against an expected manifest. Out of scope for initial delivery; add if manual testing proves flaky.

## Cost Estimate

For a ~100-file TypeScript project, full rebuild:

| | Today (Sonnet indexer) | New (Sonnet planner + Haiku writers) |
|---|---|---|
| Model token mix | ~80k Sonnet tokens | ~15k Sonnet + ~90k Haiku |
| Relative cost | 1.0× | ~0.35× |
| Wall clock | Sequential | Parallel writers (~N× speedup) |

`/index update` for a small batch (≤15 files, 2 topics) is pure-Haiku, negligible cost.

## Migration

1. Delete `agents/indexer.md`.
2. Add `agents/index-planner.md`, `agents/index-writer.md`.
3. Update `commands/index.md` — dispatch planner, add `update` subcommand.
4. Update `skills/index-generator/SKILL.md` — remove full-rebuild process, keep format specs, update pending.md thresholds.
5. Update `skills/project-index/SKILL.md` — update pending.md thresholds and suggestions.
6. Update `README.md` — add "When to run what" table, document auto-update flow.
7. Bump `.claude-plugin/plugin.json` version: `0.1.0` → `0.2.0`.

Existing users' `.claude/index/` directories remain valid — the output format is unchanged, only the generation pipeline changes. No data migration needed.

## Open Questions

None identified during brainstorming.
