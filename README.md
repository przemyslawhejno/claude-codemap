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
   - `symbols.md` — flat name → path lookup for every defined symbol (one-read answer to "where is X?")
   - Topic files — grouped by domain (`api-routes.md`, `data-models.md`, etc.)
2. On each question:
   - If it names a specific symbol (function, class, route, etc.), Claude reads `symbols.md` and jumps straight to the source file.
   - Otherwise Claude reads `INDEX.md`, picks relevant topics, and goes directly to source files.
3. A PostToolUse hook tracks every file you edit to `.claude/index/pending.md`.
4. When Claude sees `pending.md`, it acts per the threshold:
   - **≤ 15 files** → updates affected topics inline in the current session (automatic, no command needed — handled by the `project-index` skill)
   - **16–50 files** → suggests `/index update` (Haiku-powered, runs in parallel)
   - **> 50 files** → suggests `/index` full rebuild
5. The index lives in your repo — commit it so it persists across sessions.

## Pipeline

Full rebuild (`/index`) uses a two-tier agent pipeline to keep costs down:

- **`index-planner`** (Sonnet) — scans structure, decides 3–10 topics, dispatches writers, assembles INDEX.md.
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
| Skill | `skills/project-index/SKILL.md` | How Claude uses the index (INDEX.md + symbols.md lookup) |
| Skill | `skills/index-generator/SKILL.md` | Shared format reference (INDEX.md, symbols.md, topic files) |
| Agent | `agents/index-planner.md` | Sonnet planner — dispatches writers |
| Agent | `agents/index-writer.md` | Haiku per-topic worker |
| Hook | `hooks/track-changes.sh` | Tracks file edits to pending.md |
