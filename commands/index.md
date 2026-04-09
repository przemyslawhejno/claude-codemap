---
description: "Generate or rebuild project index for fast file lookup"
argument-hint: "[--compact|--detailed|status]"
---

Project index command. Generates `.claude/index/` for fast file navigation.

**Parse arguments from `$ARGUMENTS`:**

- **No arguments or `rebuild`**: Full rebuild
- **`--compact`**: Force compact mode (files + descriptions only)
- **`--detailed`**: Force detailed mode (files + signatures + descriptions)
- **`status`**: Show index status (no rebuild)

## If `status`:

1. Check if `.claude/index/INDEX.md` exists
2. If no: report "No index found. Run `/index` to generate."
3. If yes: read INDEX.md header (Generated date, Level, Files count), count topic files in `.claude/index/`, check if pending.md exists and how many entries it has
4. Report status summary

## If rebuild (default):

1. **Announce:** "Indexing project..."
2. **Invoke the `index-generator` skill** to understand the generation rules
3. **Dispatch the `indexer` agent** with task: "Scan project at current working directory. Generate complete index in .claude/index/. Detail level override: [--compact|--detailed|auto]."
4. **After agent completes:** check if this is the first run (no `## Project Index` section in CLAUDE.md)
5. **If first run:** append to CLAUDE.md:

```
## Project Index
This project uses `.claude/index/` for fast file lookup.
Before searching for files, read `.claude/index/INDEX.md` to find relevant topic files.
If `.claude/index/pending.md` exists, update affected topic files before answering.
After completing a task, suggest `/compact` if context is heavy.
```

6. **Report results:** topics created, files indexed, detail level
7. **Suggest commit:** "Index generated. Suggest: `git add .claude/index/ && git commit -m 'chore: update project index'`"
   - If first run, also include CLAUDE.md in the commit suggestion
