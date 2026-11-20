# The prompt

Unzip or clone the kit somewhere, open Claude Code **in that folder**, and paste everything below
the line. It installs the kit, proves each gate actually fires, and then tailors your repos so the
gates have something to enforce. You don't need to fill anything in first: it asks.

---

I've got a Claude Code workflow kit in the current directory. Read `README.md` and `CHEATSHEET.md`
first, then set it up for me. Work through the phases in order and stop at the checkpoint in each
phase before moving on.

**Phase 0: get to know me.**
Ask me, in one message: (1) how comfortable I am with git and the terminal (new / some / daily),
(2) which repos or parent folder I want this used on, or "none yet". Adapt to the answer for the
rest of the setup: if I'm new, explain each phase in two plain sentences before running it, and
avoid jargon or define it on first use. If I have no repos yet, skip Phase 4.

**Phase 1: inspect before installing.**
Read `install.sh`, all four scripts in `hooks/` (the two gates, the usage logger the commit gate
reads, and the status line), and the frontmatter of every file in `skills/` and `commands/`. Then
tell me, in under 15 lines: what will be written where, what will be added to my
`~/.claude/settings.json`, and anything in there you think is a bad idea. Check that `jq`, `node`
and `git` are installed (the installer only checks `jq`, but the plan gate needs `node`); if one is
missing, tell me the install command and stop. Don't install yet.

**Phase 2: install.**
Run `./install.sh`. If I already have skills or commands with the same names, it skips them. List
what it skipped and show me a diff of mine vs the kit's so I can decide which to keep. Note that
the hook scripts in `~/.claude/hooks/` are always overwritten, not skipped: if I had my own file
with the same name, say so. Confirm `~/.claude/settings.json` is still valid JSON, tell me the
backup file's name, and give me the one command that restores it if I want to undo everything.

**Phase 3: prove the gates work.** Don't take the install on faith. First run the bundled suite:
`bash test/run-hooks.sh` (temp dirs + fake HOME, touches nothing of mine) and show me the tail of
its output; every assertion must pass. If anything fails, fix it and tell me what was wrong. Then
verify by hand:
1. Create a throwaway git repo in a temp dir with one committed file, then change that file.
2. Feed the commit gate a realistic hook payload on stdin and show me the raw JSON it returns: it
   must be a `deny`. Then point `CLAUDE_SKILL_LOG` at a temp file containing a fake review line for
   that repo, re-run it, and show that it now allows. Never write to my real
   `~/.claude/skill-usage.log`.
3. Same for the plan gate: pipe it a payload with a plan that lacks the `plan-reviewed` marker
   (expect `deny`) and one that has it (expect exit 0, no output).
Report both results as a small table. If a gate doesn't behave as documented, fix it and say what
was wrong.

Then tell me to **start a new Claude Code session**: hooks are loaded when a session starts, so
this one does not have the gates armed yet.

**Phase 4: make the gates worth having by writing my `CLAUDE.md` files.**
The gates enforce that a review *happens*; a repo's `CLAUDE.md` is what makes that review *smart*:
`/review-plan` and `/loopit` both read it to derive the rules they must respect. For each repo I
named in Phase 0, inspect it (stack, CI config, git log style, deploy path, test commands) and
draft a short `CLAUDE.md` covering only what a reviewer couldn't infer from the code:
- how it gets deployed, and what a push actually triggers (which branch, which CI, what's manual)
- the branch rule ("never push X directly"), and anything irreversible I should be asked about first
- how to run its tests/typecheck/lint, and what "verified" means here
- gotchas that already burned someone (ordering traps, config that must be merged not overwritten,
  hand-applied DB steps)
- commit message convention, taken from the actual `git log`
Keep each one under ~40 lines and factual, no aspirational process. If a repo already has a
`CLAUDE.md`, propose additions to it instead of a rewrite. Show me each draft before writing it.

**Phase 5: the rules that hooks should enforce, not prose.** (If I said I'm new, offer to skip
this phase and come back later.)
Ask me which operations in my work are genuinely irreversible or need my explicit say-so every
time (candidates: pushing to production, running SQL against a live DB, deploying, force-pushing,
`rm -rf`, touching a client's server). For each one I confirm, propose the smallest possible
`PreToolUse(Bash)` hook that denies it with a message telling you to ask me first. Show me the
scripts and the exact settings.json diff; install only what I approve, and test each one the way
Phase 3 tested the gates. A rule that lives only in a `CLAUDE.md` sentence is a rule that gets
skipped under pressure, and that's the whole point of this kit.

**Phase 6: hand it back.**
Point me at `CHEATSHEET.md` instead of writing a new one, and add only what is specific to my
setup: the hooks I added in Phase 5 and how to bypass each gate. Then show me how to start a task
queue with `/loopit` using a real, small chore from one of my repos as the example (write the
`loop-tasks.md`, don't run it). End with a 3-line "first thing to try in your new session".

Rules for this whole setup:
- Show me before you write, for anything outside the kit's own folder and `~/.claude/`.
- Never modify a git repo of mine in these phases beyond creating a `CLAUDE.md` I approved.
- If something in the kit is broken or dumb on my machine, say so plainly instead of installing it.
- Don't add anything that isn't in the kit or that I didn't ask for.
