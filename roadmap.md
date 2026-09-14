# Roadmap - claude-code-skills

## Existing Features

- [x] `/review-deep` - deep multi-agent code review (4 parallel reviewers + adversarial skeptic verification, diff-sized fan-out)
- [x] `/review-plan` - pre-implementation plan review (assumptions, failure paths, blast radius, devil's advocate, Go/Adjust/Rethink verdict)
- [x] `/init-agents` - agent-team scaffolder (stack detection, agents/commands/hooks templates, minimal/full tiers, uninstall)
- [x] `/loopable` - automation scout + builder (mines recurrence signals, ranks candidates, then plan → /review-plan → implement → /review-deep → commit → ticket)
- [x] `/review` - fast single-pass pre-commit review (no subagents; the everyday one)
- [x] `/battle-test` - runnable-checks gate: AUTO/BOOTABLE/MANUAL triage, blast-radius preflight, score out of 100 + the human-only list
- [x] `/frontend-verify` - end-to-end frontend verification (console + network first, snapshots only on failure); Playwright-backed
- [x] `/security-audit` - OWASP-style scan (secrets, auth, injection, config); counts as a review for the commit gate
- [x] `/choices` - turn blocking product decisions into a message a non-technical stakeholder can answer
- [x] `/commit` - commit staged work with a why-focused message, refreshing `CLAUDE.md` when the change invalidates it
- [x] `/loopit` - autonomous task-queue runner, one subagent per task (plan → review-plan → build → verify → review → battle-test → commit → push → client note)
- [x] `/explain-dev` + `/vulgarize` - client-facing change notes (structured template / casual text), EN + FR
- [x] `/sessions` - recent sessions with their `claude --resume` commands
- [x] `/skill-stats` - usage leaderboard from the durable log
- [x] **Hooks** - the plan-review gate, the commit-review gate, the usage logger they read, and a review-state status line
- [x] `install.sh` - one-shot installer (idempotent, skips existing, **merges hook wiring into settings.json** with a backup)
- [x] `test/run-hooks.sh` - 31 assertions proving the hooks behave as documented (fake HOME, temp repos); `HOOKS=<dir>` targets an installed copy
- [x] `CHEATSHEET.md` (plain-words guide) + `ONBOARDING-PROMPT.md` (paste-in setup prompt)
- [x] README with install + usage instructions
- [x] MIT license

## Planned

- [ ] Additional generic skills from the private collection (candidates: `/create-skill`, `/diagnose`, `/guard`)
- [ ] A generic consent-gate template (deny irreversible ops until explicitly approved) - the private original encodes client-specific rules, so it needs a config-driven rewrite before it can ship
- [ ] Screenshots / sample review output in README

## Changelog

### 2026-09-14 - commit gate: per-repo bypass marker, subshell and group targets

**Re-install the commit gate if you use it.** Two fixes, both proven by the test suite against the
previous release (31 -> 39 assertions, 8 of the new ones fail on the old hook):

- The bypass marker was one global file, `~/.claude/.skip-commit-review`: any commit in any repo, from
  any session, consumed a marker created for another repo. It is now per repo,
  `~/.claude/.skip-commit-review-<repo>-<crc>`, and the deny message prints the exact path. The old
  global marker no longer unlocks anything.
- `(cd <repo> && git commit)`, `{ cd <repo>; git commit; }` and `sh -c "cd <repo> && git commit"`
  were gated against the session's cwd instead of `<repo>`: with a reviewed cwd, an unreviewed commit
  into another repo went through. `cd` is now recognised after `(`, `{` and a double quote.
- README: a review only counts when the session that ran it sits inside the repo (a subagent inherits
  its parent session's working directory).

### 2026-08-17 - commit-gate security fix, 5 new skills, /loopit v2

**The commit gate was passing unreviewed commits. Re-install if you use it.** It resolved the
target repo from the session's cwd alone, so `cd <repo> && git commit` and `git -C <repo> commit`
were gated against the wrong repo in both directions. Measured against the previous release:

| payload (session sits in reviewed repoA) | correct | 2026-07-26 | now |
|---|---|---|---|
| `cd repoB && git commit` | deny | **allow** | deny |
| `git -C repoB commit` | deny | **allow** | deny |
| `cd repoA && git commit` from repoB | allow | **deny** | allow |
| `git -C "/a path/with spaces" commit` | deny | **allow** | deny |

The dangerous rows are the ones marked allow: an unreviewed commit passed whenever the session
happened to sit in some other, recently reviewed repo. The gate now reads the target out of the
command, expands `~`, resolves relative paths against cwd, and trusts the result only if it is
genuinely a repo, so a misparse degrades to the old behaviour instead of inventing a pass. A `-C`
or `cd` appearing inside a commit *message* is not mistaken for the target.

**Second, separate hole, found while testing the first:** the pattern that decides "is this even a
commit?" matched the `-C` argument as `[^ ]+`, so a **quoted repo path containing a space**
(`git -C "~/My Projects/app" commit`) did not match at all and the commit was left *completely*
ungated, review or no review. Anyone whose projects live under a path with a space was unprotected
for that command form. Both fixes ship together. `install.sh` overwrites hooks, so re-running it
picks them up.

- Test suite 22 → 31 assertions; 6 of the 9 new ones fail against the previous release, which is
  what makes them a regression test rather than decoration.
- **`/battle-test`** - the runnable-checks gate `/loopit` Step 6 delegates to. Buckets every check
  as AUTO / BOOTABLE / MANUAL, refuses anything that could reach real data or a real user, and
  returns a score plus the human-only list.
- **`/frontend-verify`** - end-to-end frontend verification; `/battle-test`'s browser pass delegates
  to it. Adds Playwright to the requirements.
- **`/security-audit`**, **`/choices`**, **`/commit`** ported. `security-audit` was added to the
  review whitelist in **both** `commit-review-gate.sh` and `statusline.sh` - changing only one would
  make the status line disagree with the gate.
- **`/loopit` rewritten (225 → 430 lines)**: each task now runs in its own subagent, so task #8 no
  longer pays to re-read everything tasks #1-7 left in context. Adds a dead-subagent reconciliation
  procedure (establish truth from the repo, not the report), a runaway guard, a clean-tree check
  between dispatches, an "already exists?" lookup before additive work, and an append-only
  manual-steps file. Step 6 became `/battle-test`; the private Jira/ticketing step was dropped
  rather than ported.
- `/review` and `/review-deep` each gained an observability check (silent catches, swallowed errors,
  secrets/PII in logs). `/review-plan` gained the "prove it does not already exist" gate.
- Deliberately **not** synced: `/explain-dev` and `/vulgarize`, whose public forks are better than
  the private originals (English-first and de-identified, where the private ones are French-only and
  carry client-specific pricing rules). Same for `/loopable`, `/sessions` and `/init-agents`.
- Still not shipped: `ui-ux-pro-max` (third-party, no licence) and the consent-gate hook (see
  Planned).

### 2026-07-26 — hooks, /review, /loopit, client-note commands, test suite
- **The gates now ship.** Ported `plan-review-gate.mjs` (PreToolUse ExitPlanMode) and `commit-review-gate.sh` (PreToolUse Bash) plus `log-skill.sh` (the usage log the commit gate reads) and `statusline.sh` (`branch | N dirty | reviewed / UNREVIEWED`). Until now the repo shipped the reviews but nothing that made them happen.
- Three defects fixed in the commit gate while porting, each found by executing it rather than reading it: (1) it compared git's **physical** repo root against the log's **logical** cwd, so a repo under a symlinked path denied commits forever; (2) missing `jq` made it fail **open** — the gate silently ceased to exist; (3) `date -r` used BSD-only semantics, replaced by `git log --date=format-local`.
- Ported `/review` (fast single-pass), `/loopit` (autonomous task-queue runner), `/explain-dev` + `/vulgarize` (client notes, EN/FR), `/sessions`, `/skill-stats`.
- Refreshed `/review-plan` from the private original: proportionality rule, state the plan file's path (parallel sessions write plans too), prefer a runnable read-only check for the riskiest assumption, a repo-rules grep step, and a fault-attribution audit.
- `install.sh` now also installs hooks and **merges the wiring into `~/.claude/settings.json`** (timestamped backup, idempotent via a parsed-value check — a `grep` misses it because the file stores `\"` escaped). Claims `statusLine` only when unset.
- Added `test/run-hooks.sh` — 22 assertions (deny/allow paths, subdir cwd, stale review, `git -C`/`git -c` forms, `--no-verify`, one-shot bypass, malformed payload, logger false-positives). `HOOKS=~/.claude/hooks` runs them against an installed copy.
- Added `CHEATSHEET.md` and `ONBOARDING-PROMPT.md`; README restructured around the two gates.
- Deliberately **not** shipped: the private `ui-ux-pro-max` skill (third-party, arrived without a licence) and the private consent-gate hook (encodes client-specific deploy/DB rules — see Planned).
- `/loopable` kept the repo's own wording, which was better generalized than the private fork it came from.

### 2026-06-16 — /loopable skill
- Ported `/loopable` (automation scout + builder) from private collection — sanitized client names and the private `/jira` dependency (ticket step now writes markdown directly); composes in-repo `/review-plan` + `/review-deep`
- README: loopable table row + usage block; roadmap updated

### 2026-06-04 — /init-agents + installer (8406533 → this commit)
- Ported `/init-agents` skill (15 files: 6 agent templates, 4 pipeline commands, 2 hooks, settings partial) — verified clean of private references
- Added `install.sh` (tested fresh + idempotent re-run in sandboxed HOME)
- README: init-agents section, install-script instructions
- GitHub topics added for discoverability

### 2026-06-04 — Initial release (8406533)
- Imported sanitized `/review-deep` (skill) and `/review-plan` (slash command) from private collection
- Added README, MIT license, roadmap
