---
name: commit
description: Commit staged changes, update CLAUDE.md and memory if relevant
---

# Commit & Self-Maintain CLAUDE.md + Memory

## Step 1: Commit

1. Run `git status` (never use `-uall`), `git diff --cached`, and `git log --oneline -5` in parallel.
2. Analyze all staged changes. Draft a concise commit message:
   - Use conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `chore:`, etc.
   - Focus on **why**, not what.
   - NEVER include `Co-Authored-By` lines or mention Claude.
3. Stage relevant untracked files if needed (prefer specific files over `git add .`).
4. Commit using a HEREDOC for the message. Do NOT use `--no-verify`.
5. Run `git status` to confirm success.

## Step 2: Update ROADMAP.md

After committing, update `ROADMAP.md` at the project root.

1. **Gitignore rule:** `ROADMAP.md` should normally be tracked by git and committed alongside the changes it describes. Only leave it gitignored if that specific repo already does so.
2. Read the current `ROADMAP.md` (create it if it doesn't exist).
3. **Prepend** a new entry at the top (most recent first) with this format:

```
## [commit hash short] - [commit message] ([date YYYY-MM-DD])

**Problem:** [What was wrong or missing - 1-2 sentences]

**Solution:** [What was done to fix/implement it - 1-2 sentences]

**Files changed:** [list of key files touched, not exhaustive]

---
```

4. Keep entries concise and useful. Focus on the **why** and the **how**, not line-by-line diffs.
5. If the commit is trivial (typo fix, formatting), still add an entry but keep it minimal.

## Step 3: Evaluate CLAUDE.md Relevance

After committing, read the project's CLAUDE.md (if one exists) and review the committed diff against it.

**Update CLAUDE.md ONLY if the commit changed something the file already documents or should document:**

- A new backend function/endpoint/service → add to whatever list tracks those
- A new data model/entity/schema → add to whatever list tracks those
- A changed core flow (auth, payments, data pipeline, etc.) → update the relevant section
- A new critical constraint or gotcha discovered → add to constraints/warnings section
- An architecture shift (new library, new pattern, new convention) → update architecture docs
- A removed or renamed component that CLAUDE.md references → fix the stale reference

**Do NOT update CLAUDE.md for:**
- Bug fixes that don't change architecture
- UI tweaks, styling, or cosmetic changes
- Routine feature work that follows existing patterns
- Anything speculative - only document confirmed facts

## Step 4: If Updating CLAUDE.md

1. Read the current CLAUDE.md.
2. Make minimal, surgical edits - add a bullet, update a list, fix a stale reference.
3. Respect the file's existing structure and style. Don't reorganize it.
4. If the file is growing long, consider condensing older info rather than appending.
5. **Before committing CLAUDE.md**, check if it's in `.gitignore`. If it is, skip the commit - just edit it locally. If it's NOT in `.gitignore`, create a separate commit: `docs: update CLAUDE.md - [brief reason]`.

## Step 5: Evaluate Memory Relevance

After committing, check if any of these should be saved to memory:

- **User feedback** received during this session (corrections, preferences, "don't do X") → save as `feedback` memory
- **Project context** learned (who's doing what, why, deadlines, business decisions) → save as `project` memory
- **Investigation/debugging findings** discovered during this session (error patterns, log analysis results, root cause analysis, affected users, ongoing unresolved issues) → save as `project` memory with current status and key data points. When updating an existing project memory, preserve history: mark what was fixed vs what remains open.
- **User profile** details learned (role, expertise, preferences) → save as `user` memory
- **External references** discovered (where to find info, dashboards, tools) → save as `reference` memory

**Do NOT save to memory:**
- Code patterns or architecture (that's what CLAUDE.md is for)
- Anything already in CLAUDE.md or derivable from code/git
- Ephemeral task details only relevant to current conversation

If saving, write to the memory directory and update MEMORY.md index.

## Step 6: Report

Tell the user:
- What was committed (short summary)
- Whether ROADMAP.md was updated
- Whether CLAUDE.md was updated and why (or "no update needed - [reason]")
- Whether memory was updated and why (or "no memory update needed")
