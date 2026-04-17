# Flat Symbol Index Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a flat `symbols.md` file to `.claude/index/` that maps every named declaration to its source path, so Claude answers "where is X?" in one read.

**Architecture:** Extend the existing two-tier pipeline (Sonnet planner + Haiku writers). Writers emit a `symbols:` block alongside their topic file. Planner concatenates slices, sorts, caps at 3000, writes `symbols.md`. `/index update` does partial rewrite by replacing slices from affected topics.

**Tech Stack:** Claude Code plugin — Markdown (agents, skills, commands). No code, no tests; verification is structural grep on the final files.

**Spec:** `docs/superpowers/specs/2026-04-17-flat-symbol-index-design.md`

---

## File Structure

All changes are to existing files. No new files are introduced at implementation time; `.claude/index/symbols.md` itself is produced by running the plugin, not by this plan.

| File | Responsibility |
|---|---|
| `skills/index-generator/SKILL.md` | Format spec for `symbols.md` (shared reference) |
| `agents/index-writer.md` | Emit `symbols:` block in writer report |
| `agents/index-planner.md` | Compose `symbols.md` from slices; add topics line |
| `commands/index.md` | `update` flow: partial `symbols.md` rewrite |
| `skills/project-index/SKILL.md` | Named-symbol lookup rule for main session |
| `README.md` | Mention symbols in structure + usage table |
| `.claude-plugin/plugin.json` | Version bump 0.2.0 → 0.3.0 |

## Verification note

This plugin has no automated tests — artifacts are Markdown files consumed by Claude Code. Each task's "test" step uses `grep` / file reads to verify the text was actually added. Functional smoke testing (`/index` on a real project) happens in a fresh Claude Code session after publish, as a follow-up task.

---

## Task 1: Add `symbols.md` format section to the index-generator skill

This is the shared format reference writers and planner will cite. Writing it first so later tasks can point at this section.

**Files:**
- Modify: `skills/index-generator/SKILL.md` — insert new section after `## Topic File Format — Compact`

- [ ] **Step 1: Read current skill file**

Run: `cat skills/index-generator/SKILL.md | head -80`
Expected: see existing sections including `## Topic File Format — Compact`.

- [ ] **Step 2: Insert symbols.md format section**

After the `## Topic File Format — Compact` section and before `## Skip List (Structure Scan)`, insert:

```markdown
## symbols.md Format

Flat, alphabetical-by-name symbol index for one-read "where is X?" lookups. Produced once per rebuild and kept in lockstep with topic files on `/index update`.

```
# Symbols
Generated: YYYY-MM-DD
Count: N

[class] AuthService → src/auth/service.ts:12
[cmd]   index → commands/index.md:1
[component] LoginForm → web/src/LoginForm.tsx:8
[const] MAX_RETRIES → src/config.ts:5
[enum]  Status → src/types.ts:20
[fn]    parseConfig → src/config.ts:42
[route] GET /users → src/api/users.ts:15
[type]  User → src/types.ts:3
```

**Line format:** `[kind] name → path:line`

**Kinds (fixed set of 8):**
- `fn` — functions, methods
- `class` — classes
- `type` — types, interfaces, type aliases
- `enum` — enums
- `route` — HTTP routes / endpoints (`METHOD /path`)
- `const` — top-level constants
- `component` — React / Vue / Svelte components
- `cmd` — CLI commands / slash commands

**Ordering:** alphabetical by `name`, case-insensitive.

**Size cap:** 3000 symbols. Past cap, truncate and append a final line:

```
> N symbols omitted — fall back to Grep for uncommon names
```

**Scope:** named declarations only. Skip local variables, inline lambdas, test cases, doc anchors.

**Usage:** the main session reads `symbols.md` first when the user's question names a specific symbol; falls back to INDEX → topic flow for conceptual questions.
```

- [ ] **Step 3: Verify the section is present**

Run: `grep -c '^## symbols.md Format' skills/index-generator/SKILL.md`
Expected: `1`

Run: `grep -c '\[fn\] — functions' skills/index-generator/SKILL.md`
Expected: `1`

- [ ] **Step 4: Commit**

```bash
git add skills/index-generator/SKILL.md
git commit -m "feat(index-generator): add symbols.md format spec"
```

---

## Task 2: Update `index-writer` agent to emit a symbols block

The writer already reads its topic files to extract signatures. This task adds a `symbols:` block to the writer's report, using the same pass.

**Files:**
- Modify: `agents/index-writer.md`

- [ ] **Step 1: Read current writer agent**

Run: `cat agents/index-writer.md`
Expected: see workflow phases and the "Report back" section at the end.

- [ ] **Step 2: Add a symbol-extraction step to the writer workflow**

Find the phase where the writer extracts signatures (it already uses Grep/Read on assigned files). Add a new phase immediately after signature extraction and before topic-file writing. Insert this text:

```markdown
### Phase 2b — Collect symbols for the flat symbol index

While you have the files open for signature extraction, record every named declaration for the shared `symbols.md` index. This is the same pass — do not re-read files.

For each assigned file, identify:
- functions / methods → `[fn]`
- classes → `[class]`
- types, interfaces, type aliases → `[type]`
- enums → `[enum]`
- HTTP routes / endpoints (`app.get('/users')`, Flask decorators, FastAPI routes, Express, etc.) → `[route]` with value `METHOD /path`
- top-level constants (exported or module-level) → `[const]`
- React / Vue / Svelte components → `[component]`
- CLI commands / slash commands (files under `commands/`, click / commander / cobra entries) → `[cmd]`

Skip: local variables inside functions, inline lambdas, test cases (`it()`, `test()`, `describe()`), doc anchors, auto-generated code.

Record each as:

```
[kind] name → path:line
```

Use the file path exactly as it appears in your assigned `files` list (relative to project root). `line` is the 1-based line where the declaration starts.

**Fixed kind set** — use only these 8 tags: `fn`, `class`, `type`, `enum`, `route`, `const`, `component`, `cmd`. Do not invent new tags.
```

- [ ] **Step 3: Update the writer's report format to include the symbols block**

Find the "Report back" (or equivalent) section at the end of the agent workflow. Replace or extend it so the writer's final report includes this block. Insert (or merge into) the report format:

```markdown
## Report format

Report back to the planner with exactly these fields:

- `file_count` — number of files actually read
- `skipped` — files skipped (with reason)
- `truncated` — whether the topic file hit the 200-line cap
- `fallback_to_compact` — whether detail level was downgraded for size
- `symbols` — a fenced block of symbol lines (one per line, format `[kind] name → path:line`). May be empty if the topic contains no named declarations.

Example:

```
file_count: 3
skipped: []
truncated: false
fallback_to_compact: false
symbols:
  [fn] parseConfig → src/config.ts:42
  [class] AuthService → src/auth/service.ts:12
  [route] GET /users → src/api/users.ts:15
```
```

If a report section already exists, merge the `symbols` field into it rather than duplicating.

- [ ] **Step 4: Verify**

Run: `grep -c 'Phase 2b' agents/index-writer.md`
Expected: `1`

Run: `grep -c 'symbols:' agents/index-writer.md`
Expected: at least `1`

Run: `grep -c 'Fixed kind set' agents/index-writer.md`
Expected: `1`

- [ ] **Step 5: Commit**

```bash
git add agents/index-writer.md
git commit -m "feat(index-writer): emit symbols block for flat symbol index"
```

---

## Task 3: Update `index-planner` agent to compose `symbols.md`

The planner receives symbol slices from every writer. Add a new phase that concatenates, dedupes, sorts, caps, and writes `.claude/index/symbols.md`. Also add the symbols entry to INDEX.md's Topics list.

**Files:**
- Modify: `agents/index-planner.md`

- [ ] **Step 1: Read current planner agent**

Run: `cat agents/index-planner.md`
Expected: see Phases 1–5 including "Phase 4 — Assemble INDEX.md".

- [ ] **Step 2: Add Phase 4b (compose symbols.md) after Phase 4**

Insert this phase between existing Phase 4 (Assemble INDEX.md) and Phase 5 (Cleanup and report). Number it Phase 4b so downstream numbering stays stable:

```markdown
### Phase 4b — Compose symbols.md from writer slices

After all writers have reported and before cleanup, build the flat symbol index.

1. Concatenate the `symbols:` block from every writer's report into one list of lines.
2. Deduplicate — drop any line identical (byte-for-byte after trimming whitespace) to another. Two writers reporting the same file is a rare edge case but handle it silently.
3. Sort alphabetically by the `name` field (between `]` and `→`), case-insensitive. Ties: order by path.
4. Apply the 3000-line cap. If the list is longer:
   - Keep the first 3000 lines
   - Append a single trailing line: `> N symbols omitted — fall back to Grep for uncommon names` where N is the number dropped
5. Write `.claude/index/symbols.md` with this header and the processed list:

```
# Symbols
Generated: <today's date in YYYY-MM-DD>
Count: <number of symbol lines, not counting the truncation note if present>

<sorted lines here>
```

Format spec: see the `symbols.md Format` section of the `index-generator` skill.
```

- [ ] **Step 3: Add the symbols entry to the Topics list in Phase 4**

Find Phase 4 ("Assemble INDEX.md"). Locate where it describes building the `## Topics` list. Add an instruction that the Topics list must include the `symbols` entry as the first item. Insert this text inside Phase 4, immediately after the bullet describing the Topics section:

```markdown
   - **Always include `symbols` as the first entry in the Topics list:**
     `- [symbols](symbols.md) — flat name → path lookup for all defined symbols`
     This applies even for small-project fallback with a single `overview.md` topic.
```

- [ ] **Step 4: Update the planner's final report to mention symbols**

Find Phase 5 ("Cleanup and report"). Add one bullet to its summary list:

```markdown
    - Symbols indexed (count from symbols.md header; note if truncation applied)
```

- [ ] **Step 5: Verify**

Run: `grep -c 'Phase 4b' agents/index-planner.md`
Expected: `1`

Run: `grep -c 'symbols.md' agents/index-planner.md`
Expected: at least `3` (Phase 4b, Topics entry, report bullet)

Run: `grep -c 'first entry in the Topics list' agents/index-planner.md`
Expected: `1`

- [ ] **Step 6: Commit**

```bash
git add agents/index-planner.md
git commit -m "feat(index-planner): compose symbols.md from writer slices"
```

---

## Task 4: Update `/index update` to partially rewrite `symbols.md`

When `/index update` regenerates only the affected topics, symbols belonging to files in those topics must be replaced; symbols from unaffected topics stay.

**Files:**
- Modify: `commands/index.md`

- [ ] **Step 1: Read current command file**

Run: `cat commands/index.md`
Expected: see the `## If update` section describing writer dispatch for affected topics.

- [ ] **Step 2: Add symbols.md handling to the update flow**

Inside the `## If update` section, after the step "After all writers complete, delete `.claude/index/pending.md`" (or wherever the post-writer cleanup lives), insert a new numbered step *before* the pending.md deletion:

```markdown
N. **Rewrite `.claude/index/symbols.md` partially:**
   1. Read the existing `.claude/index/symbols.md` if present. If absent, skip this step entirely — next full `/index` rebuild will create it.
   2. Collect the list of file paths belonging to the affected topics (the same list passed to the writers).
   3. From the existing symbols.md body, drop every line whose `path` portion (between `→ ` and `:`) matches any file in that list. Keep all other lines.
   4. Append the fresh `symbols:` blocks from the re-run writers' reports.
   5. Deduplicate (byte-for-byte after trimming).
   6. Sort alphabetically by name, case-insensitive.
   7. Apply the 3000-line cap with the truncation note (`> N symbols omitted — fall back to Grep for uncommon names`) if needed.
   8. Rewrite `.claude/index/symbols.md` with an updated header:
      ```
      # Symbols
      Generated: <today's date>
      Count: <new count>
      ```
```

Renumber subsequent steps so the pending.md deletion and the final report come after this step.

- [ ] **Step 3: Mention symbols in the update report**

Find the final reporting step of the update flow (e.g. "Report: topics updated ..."). Extend it with:

```markdown
   Also report: symbols.md status (rewritten / skipped because not present / unchanged if no affected symbols).
```

- [ ] **Step 4: Verify**

Run: `grep -c 'symbols.md' commands/index.md`
Expected: at least `2`

Run: `grep -c 'Rewrite .*symbols.md. partially' commands/index.md`
Expected: `1`

- [ ] **Step 5: Commit**

```bash
git add commands/index.md
git commit -m "feat(index command): partial symbols.md rewrite on /index update"
```

---

## Task 5: Add named-symbol lookup rule to `project-index` skill

Teach the main session to check `symbols.md` first when the user names a specific symbol.

**Files:**
- Modify: `skills/project-index/SKILL.md`

- [ ] **Step 1: Read current skill file**

Run: `cat skills/project-index/SKILL.md`
Expected: see existing usage rules describing the INDEX → topic flow.

- [ ] **Step 2: Insert the named-symbol lookup rule**

Near the top of the "how to use the index" rules (before the general INDEX → topic description), insert this subsection:

```markdown
## Named-symbol lookup (check this first)

When the user's question names a specific symbol — a function, class, type, interface, enum, route, constant, component, or CLI command — read `.claude/index/symbols.md` first.

Examples that trigger symbol lookup:
- "where is `parseConfig` defined?"
- "show me the `AuthService` class"
- "which file handles `GET /users`?"
- "find the `<LoginForm>` component"

Steps:
1. Read `.claude/index/symbols.md` if it exists.
2. Grep for the symbol name. Lines look like `[kind] name → path:line`.
3. Open the referenced file and jump to the line.
4. Only fall back to `INDEX.md` → topic files if the symbol is absent from `symbols.md` or you need broader context (e.g. "how does auth *work*?" is conceptual, not a name lookup).

If `symbols.md` is missing, the index predates this feature or was not regenerated — suggest `/index` to the user.
```

- [ ] **Step 3: Update the INDEX → topic section to reference the new rule**

Find the existing rule that says "read INDEX.md first" (or equivalent). Add a short preamble to that rule:

```markdown
For conceptual questions (no specific symbol named), use the INDEX → topic flow below. For name-based lookups, prefer `symbols.md` per the "Named-symbol lookup" section above.
```

- [ ] **Step 4: Verify**

Run: `grep -c 'Named-symbol lookup' skills/project-index/SKILL.md`
Expected: `1`

Run: `grep -c 'symbols.md' skills/project-index/SKILL.md`
Expected: at least `3`

- [ ] **Step 5: Commit**

```bash
git add skills/project-index/SKILL.md
git commit -m "feat(project-index): add named-symbol lookup rule"
```

---

## Task 6: Update README to document symbols.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Read current README**

Run: `cat README.md`
Expected: see "How it works" section describing `INDEX.md` + topic files.

- [ ] **Step 2: Add symbols.md to the "How it works" description**

In the "How it works" section, find the bullet listing `.claude/index/` contents:

Current text:
```
1. `/index` scans your project and generates `.claude/index/` with:
   - `INDEX.md` — lightweight table of contents (~50-80 lines)
   - Topic files — grouped by domain (`api-routes.md`, `data-models.md`, etc.)
```

Replace with:
```
1. `/index` scans your project and generates `.claude/index/` with:
   - `INDEX.md` — lightweight table of contents (~50-80 lines)
   - `symbols.md` — flat name → path lookup for every defined symbol (one-read answer to "where is X?")
   - Topic files — grouped by domain (`api-routes.md`, `data-models.md`, etc.)
```

- [ ] **Step 3: Add a row to the "When to run what" table**

Leave the table as is — no new commands for symbols. Instead, in the step 2 bullet of "How it works", update it:

Current text:
```
2. On each question, Claude reads `INDEX.md`, picks relevant topics, and goes directly to source files.
```

Replace with:
```
2. On each question:
   - If it names a specific symbol (function, class, route, etc.), Claude reads `symbols.md` and jumps straight to the source file.
   - Otherwise Claude reads `INDEX.md`, picks relevant topics, and goes directly to source files.
```

- [ ] **Step 4: Verify**

Run: `grep -c 'symbols.md' README.md`
Expected: at least `3`

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs(readme): document symbols.md lookup path"
```

---

## Task 7: Bump plugin version

**Files:**
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 1: Read current manifest**

Run: `cat .claude-plugin/plugin.json`
Expected: `"version": "0.2.0"`

- [ ] **Step 2: Bump version to 0.3.0**

Edit `.claude-plugin/plugin.json`, change the `version` field from `"0.2.0"` to `"0.3.0"`.

- [ ] **Step 3: Verify**

Run: `grep -c '"version": "0.3.0"' .claude-plugin/plugin.json`
Expected: `1`

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "chore: bump version to 0.3.0"
```

---

## Task 8: Final structural verification sweep

Run all grep checks together and confirm every artifact references symbols.md consistently.

**Files:** read-only

- [ ] **Step 1: Run the consolidated verification**

```bash
echo "--- skill format spec ---"
grep -c '^## symbols.md Format' skills/index-generator/SKILL.md

echo "--- writer emits symbols ---"
grep -c 'Phase 2b' agents/index-writer.md
grep -c 'Fixed kind set' agents/index-writer.md

echo "--- planner composes symbols.md ---"
grep -c 'Phase 4b' agents/index-planner.md
grep -c 'first entry in the Topics list' agents/index-planner.md

echo "--- /index update rewrites symbols.md ---"
grep -c 'Rewrite .*symbols.md. partially' commands/index.md

echo "--- project-index skill has lookup rule ---"
grep -c 'Named-symbol lookup' skills/project-index/SKILL.md

echo "--- README mentions symbols.md ---"
grep -c 'symbols.md' README.md

echo "--- version bumped ---"
grep -c '"version": "0.3.0"' .claude-plugin/plugin.json
```

Expected: every line prints `1` (or `≥1` where noted). No `0`s.

- [ ] **Step 2: Confirm no stray references to an old format**

```bash
grep -rn 'SYMBOLS.md' . --include='*.md' || true
grep -rn 'symbol-index' . --include='*.md' || true
```

Expected: no unexpected matches (the spec uses `symbols.md` lower-case and doesn't use the phrase `symbol-index`).

- [ ] **Step 3: Check kind tag set is consistent across files**

```bash
for f in skills/index-generator/SKILL.md agents/index-writer.md; do
  echo "--- $f ---"
  grep -oE '\[(fn|class|type|enum|route|const|component|cmd)\]' "$f" | sort -u
done
```

Expected: both files reference the same 8 kind tags (not necessarily all 8 in examples, but no foreign tags).

- [ ] **Step 4: No commit for this task** — verification only. If any check fails, fix the relevant task's file and re-run.

---

## Task 9: Publish to marketplace

After implementation is complete on master, update the marketplace manifest so the plugin is installable at the new version.

**Files:**
- Modify: `/home/przemek/Development/phejno-plugins/.claude-plugin/marketplace.json`

- [ ] **Step 1: Push plugin commits to origin**

```bash
cd /home/przemek/Development/claude-project-index
git push origin master
git rev-parse HEAD
```

Record the resulting SHA — call it `NEW_SHA`.

- [ ] **Step 2: Update marketplace manifest**

In `/home/przemek/Development/phejno-plugins/.claude-plugin/marketplace.json`, for the `claude-project-index` plugin entry, set:
- `source.sha` → `NEW_SHA` from Step 1
- `version` → `"0.3.0"`

- [ ] **Step 3: Verify**

Run: `grep -A1 'claude-project-index' /home/przemek/Development/phejno-plugins/.claude-plugin/marketplace.json | head -20`
Expected: version `0.3.0` and the new SHA.

- [ ] **Step 4: Commit and push marketplace update**

```bash
cd /home/przemek/Development/phejno-plugins
git add .claude-plugin/marketplace.json
git commit -m "chore: bump claude-project-index to 0.3.0 (flat symbol index)"
git push origin master
```

- [ ] **Step 5: Refresh local marketplace cache**

```bash
cd ~/.claude/plugins/marketplaces/phejno-plugins
git pull --ff-only
```

Expected: fast-forward to the new commit.

---

## Task 10: Smoke test in fresh Claude Code session (deferred)

This cannot run in the implementation session — `/index` requires the upgraded plugin to be loaded at Claude Code startup. Carry this out in a new session:

- [ ] **Step 1:** Open a fresh Claude Code session in a project that already has a v0.2.0 index, or in this plugin's own repo.
- [ ] **Step 2:** Run `/index` — confirm `.claude/index/symbols.md` appears and the INDEX.md Topics list has `symbols` as the first entry.
- [ ] **Step 3:** Ask a named-symbol question ("where is `parseConfig`?") — confirm Claude reads `symbols.md` first per the new rule.
- [ ] **Step 4:** Edit a tracked file, then run `/index update` — confirm `symbols.md` is updated and unaffected lines stay in place.
- [ ] **Step 5:** If anything misbehaves, capture the discrepancy and open a follow-up plan.

---

## Self-review (completed by plan author)

- **Spec coverage:** every section in the spec maps to a task —
  - `File format` → Task 1
  - `Generation (writer)` → Task 2
  - `Generation (planner)` → Task 3
  - `/index update incremental` → Task 4
  - `Usage (project-index skill)` → Task 5
  - `Files to modify: README` → Task 6
  - `Guardrails (3000 cap, dedupe, kind set)` → enforced in Tasks 1, 3, 4
  - Version bump implied by spec being a feature → Task 7
- **Placeholder scan:** no TBDs, no "similar to above", every code/text block is literal.
- **Name consistency:** `symbols.md`, kind tags `fn/class/type/enum/route/const/component/cmd`, and Phase numbering (`2b`, `4b`) are used identically across all tasks.
