# claude-project-index

Claude Code plugin that generates a compact project index for fast file lookup. Reduces token usage by 60-80% on navigation tasks.

## Install

```bash
claude plugins install /path/to/claude-project-index
```

## Usage

```bash
# First time — generate index
/index

# Check status
/index status

# Force detail level
/index --compact
/index --detailed
```

## How it works

1. `/index` scans your project and generates `.claude/index/` with:
   - `INDEX.md` — lightweight table of contents (~50 lines)
   - Topic files — grouped by domain (`api-routes.md`, `data-models.md`, etc.)
2. On each question, Claude reads `INDEX.md`, picks relevant topics, and goes directly to source files
3. A PostToolUse hook tracks file changes to `pending.md` for incremental updates
4. Index lives in your repo — commit it so it persists across sessions

## Detail levels

| Level | When | Content |
|---|---|---|
| compact | <50 code files | File paths + 1-line descriptions |
| detailed | 50+ code files | File paths + signatures + descriptions |

Auto-selected based on project size. Override with `--compact` or `--detailed`.

## Nested projects

Sub-projects (detected by `.git/`, `.claude/index/`) get a pointer in the parent's INDEX.md. Each project manages its own index independently.

## Plugin components

| Component | File | Purpose |
|---|---|---|
| Command | `commands/index.md` | `/index` slash command |
| Skill | `skills/project-index/SKILL.md` | How Claude uses the index |
| Skill | `skills/index-generator/SKILL.md` | How to generate/update index |
| Agent | `agents/indexer.md` | Subagent for scanning |
| Hook | `hooks/track-changes.sh` | Track file changes |
