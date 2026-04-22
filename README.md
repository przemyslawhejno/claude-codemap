# claude-codemap

Claude Code plugin that generates a codemap for fast file lookup and symbol navigation. Reduces token usage by 60-80% on navigation tasks.

## Install

```bash
claude plugins install /path/to/claude-codemap
```

### Unqualified `/codemap` command (optional)

Plugin commands are namespaced as `/claude-codemap:codemap`. To expose it as plain `/codemap`, symlink the plugin's command file into your user commands:

```bash
bash scripts/relink-user-command.sh
```

Re-run after upgrading the plugin (the cache path includes the version).

## When to run what

| Command | When to use | What runs |
|---|---|---|
| `/codemap` | First time in a project, or when the index is stale/wrong | Full rebuild: Sonnet planner + N parallel Haiku writers (one per topic) |
| `/codemap update` | `pending.md` has many entries and you want a clean index without a full rebuild | Haiku writers only, for affected topics |
| `/codemap status` | Anytime — quick health check | Reads INDEX.md header + counts pending entries |
| `/codemap --compact` | Force compact detail level on rebuild | Same as `/codemap`, overrides auto-selection |
| `/codemap --detailed` | Force detailed detail level on rebuild | Same as `/codemap`, overrides auto-selection |

## How it works

1. `/codemap` scans your project and generates `.claude/codemap/` with:
   - `INDEX.md` — lightweight table of contents (~50-80 lines)
   - `symbols.md` — flat name → path lookup for every defined symbol (one-read answer to "where is X?")
   - Topic files — grouped by domain (`api-routes.md`, `data-models.md`, etc.)
2. On each question:
   - If it names a specific symbol (function, class, route, etc.), Claude reads `symbols.md` and jumps straight to the source file.
   - Otherwise Claude reads `INDEX.md`, picks relevant topics, and goes directly to source files.
3. A PostToolUse hook tracks every file you edit to `.claude/codemap/pending.md`.
4. When Claude sees `pending.md`, it acts per the threshold:
   - **≤ 15 files** → updates affected topics inline in the current session (automatic, no command needed — handled by the `codemap-usage` skill)
   - **16–50 files** → suggests `/codemap update` (Haiku-powered, runs in parallel)
   - **> 50 files** → suggests `/codemap` full rebuild
5. The index lives in your repo — commit it so it persists across sessions.

## Pipeline

Full rebuild (`/codemap`) uses a two-tier agent pipeline to keep costs down:

- **`codemap-planner`** (Sonnet) — scans structure, decides 3–10 topics, dispatches writers, assembles INDEX.md.
- **`codemap-writer`** (Haiku) — one per topic, reads the topic's files and writes the topic file. Run in parallel.

Incremental updates (`/codemap update`) skip the planner — Haiku writers regenerate only the affected topics.

## Detail levels

| Level | When | Content |
|---|---|---|
| compact | <50 code files | File paths + 1-line descriptions |
| detailed | 50+ code files | File paths + signatures + descriptions |

Auto-selected based on project size. Override with `--compact` or `--detailed`.

## Nested projects

Sub-projects (detected by `.git/`, `.claude/codemap/`, or language-specific markers) get a pointer in the parent's INDEX.md. Each project manages its own index independently.

## Plugin components

| Component | File | Purpose |
|---|---|---|
| Command | `commands/codemap.md` | `/codemap` slash command |
| Skill | `skills/codemap-usage/SKILL.md` | How Claude uses the index (INDEX.md + symbols.md lookup) |
| Skill | `skills/codemap-format/SKILL.md` | Shared format reference (INDEX.md, symbols.md, topic files) |
| Agent | `agents/codemap-planner.md` | Sonnet planner — dispatches writers |
| Agent | `agents/codemap-writer.md` | Haiku per-topic worker |
| Hook | `hooks/track-changes.sh` | Tracks file edits to pending.md |
