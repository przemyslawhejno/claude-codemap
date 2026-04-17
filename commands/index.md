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
