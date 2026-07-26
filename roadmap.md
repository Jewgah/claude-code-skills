# Roadmap — claude-code-skills

## Existing Features

- [x] `/review-deep` — deep multi-agent code review (4 parallel reviewers + adversarial skeptic verification, diff-sized fan-out)
- [x] `/review-plan` — pre-implementation plan review (assumptions, failure paths, blast radius, devil's advocate, Go/Adjust/Rethink verdict)
- [x] `/init-agents` — agent-team scaffolder (stack detection, agents/commands/hooks templates, minimal/full tiers, uninstall)
- [x] `/loopable` — automation scout + builder (mines recurrence signals, ranks candidates, then plan → /review-plan → implement → /review-deep → commit → ticket)
- [x] `/review` — fast single-pass pre-commit review (no subagents; the everyday one)
- [x] `/loopit` — autonomous task-queue runner (plan → review-plan → build → verify → review → commit → push → client note, per task)
- [x] `/explain-dev` + `/vulgarize` — client-facing change notes (structured template / casual text), EN + FR
- [x] `/sessions` — recent sessions with their `claude --resume` commands
- [x] `/skill-stats` — usage leaderboard from the durable log
- [x] **Hooks** — the plan-review gate, the commit-review gate, the usage logger they read, and a review-state status line
- [x] `install.sh` — one-shot installer (idempotent, skips existing, **merges hook wiring into settings.json** with a backup)
- [x] `test/run-hooks.sh` — 22 assertions proving the hooks behave as documented (fake HOME, temp repos); `HOOKS=<dir>` targets an installed copy
- [x] `CHEATSHEET.md` (plain-words guide) + `ONBOARDING-PROMPT.md` (paste-in setup prompt)
- [x] README with install + usage instructions
- [x] MIT license

## Planned

- [ ] Additional generic skills from the private collection (candidates: `/create-skill`, `/diagnose`, `/guard`)
- [ ] A generic consent-gate template (deny irreversible ops until explicitly approved) — the private original encodes client-specific rules, so it needs a config-driven rewrite before it can ship
- [ ] Screenshots / sample review output in README

## Changelog

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
