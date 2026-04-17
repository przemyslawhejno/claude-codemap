---
description: "Generate, update, or inspect the codemap for fast file lookup"
argument-hint: "[--compact|--detailed|status|update]"
---

Codemap command. Manages `.claude/codemap/` for fast file navigation.

**Parse arguments from `$ARGUMENTS`:**

- **No arguments**: Full rebuild (planner + parallel writers)
- **`--compact`**: Force compact detail level on rebuild
- **`--detailed`**: Force detailed detail level on rebuild
- **`status`**: Show index status, no changes
- **`update`**: Process `.claude/codemap/pending.md`, regenerate affected topic files

## If `status`

1. Check if `.claude/codemap/INDEX.md` exists.
2. If no: report "No index found. Run `/codemap` to generate."
3. If yes:
   - Read INDEX.md header (Generated date, Level, Files count).
   - Count topic files in `.claude/codemap/` (excluding `INDEX.md` and `pending.md`).
   - If `pending.md` exists, count unique lines in it.
4. Report status summary.

## If `update`

1. Check if `.claude/codemap/INDEX.md` exists. If not: report "No index to update. Run `/codemap` first."
2. Read `.claude/codemap/pending.md` if it exists. If missing or empty: report "Nothing pending. Index is up to date." and exit.
3. Deduplicate paths in `pending.md`.
4. If unique count > 50: report "Too many pending changes (N > 50). Run `/codemap` for full rebuild." and exit (do not auto-run).
5. Read INDEX.md to get the topic list (file names only).
6. For each topic, read `.claude/codemap/{topic}.md` and collect the list of source paths it currently references. Build `path → topic` map.
7. For each changed path in pending: match to its topic. Collect unmapped paths separately.
8. Dispatch one `codemap-writer` agent per affected topic, in parallel (single message, multiple Agent tool uses). Each writer prompt includes:
   - `topic_name`
   - `files` — the topic's **full current file list** (existing entries from the topic file, merged with any newly-changed paths mapped to this topic)
   - `detail_level` — read from INDEX.md header
   - `description` — read from INDEX.md topic line
9. **Rewrite `.claude/codemap/symbols.md` partially:**
   1. Read the existing `.claude/codemap/symbols.md` if present. If absent, skip this step entirely — next full `/codemap` rebuild will create it.
   2. Collect the list of file paths belonging to the affected topics (the same list passed to the writers).
   3. From the existing symbols.md body, drop every line whose `path` portion (between `→ ` and `:`) matches any file in that list. Keep all other lines.
   4. Append the fresh `symbols` blocks from the re-run writers' reports.
   5. Deduplicate (byte-for-byte after trimming).
   6. Sort alphabetically by name, case-insensitive.
   7. Apply the 3000-line cap with the truncation note (`> N symbols omitted — fall back to Grep for uncommon names`) if needed.
   8. Rewrite `.claude/codemap/symbols.md` with an updated header:
      ```
      # Symbols
      Generated: <today's date>
      Count: <new count>
      ```
10. After all writers complete, delete `.claude/codemap/pending.md`.
11. Report: topics updated (count + names), files processed, unmapped paths (if any, with a note that running full `/codemap` may be needed).
    Also report: symbols.md status (rewritten / skipped because not present / unchanged if no affected symbols).

## If rebuild (default, or with `--compact` / `--detailed`)

1. Announce: "Indexing project..."
2. Invoke the `codemap-format` skill via the Skill tool to load the format reference.
3. Dispatch the `codemap-planner` agent. Prompt template:

   ```
   Scan project at current working directory. Generate complete index in .claude/codemap/.
   Detail level override: [--compact | --detailed | auto]
   ```

   (Substitute the actual override based on `$ARGUMENTS`; use `auto` if neither flag is present.)
4. After the planner completes, check if this is the first run (no `## Codemap` section in `CLAUDE.md`).
5. **If first run:** append to `CLAUDE.md`:

   ```
   ## Codemap
   This project uses `.claude/codemap/` for fast file lookup.
   Before searching for files, read `.claude/codemap/INDEX.md` to find relevant topic files.
   If `.claude/codemap/pending.md` exists, update affected topic files before answering.
   Run `/codemap update` when `.claude/codemap/pending.md` grows large; `/codemap` for full rebuild.
   After completing a task, suggest `/compact` if context is heavy.
   ```

6. Report results from the planner's summary: topics created, files indexed, detail level, sub-projects, any failures.
7. Suggest commit: `git add .claude/codemap/ && git commit -m 'chore: update codemap'`
   - If first run, also include `CLAUDE.md` in the commit suggestion.
