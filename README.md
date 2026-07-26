# claude-code-skills

Battle-tested [Claude Code](https://claude.com/claude-code) skills, commands and **hooks** for shipping safely.

The core idea: the two quality steps everyone skips under pressure — reviewing the *plan* before building, and reviewing the *code* before committing — are enforced by hooks instead of by remembering to ask.

| Gate | Hook | What happens |
|---|---|---|
| **Plan review** | `PreToolUse(ExitPlanMode)` | Claude can't show you a plan until it has run `/review-plan` on it and folded the findings in. |
| **Commit review** | `PreToolUse(Bash)` | `git commit` is denied unless `/review` (or `/review-deep`, `/code-review`, `/security-review`) ran in that repo since the last commit. |

Everything else here is either what those gates run, or a tool that reuses their data.

## What's inside

| Command | Type | What it does |
|---------|------|--------------|
| `/review` | Skill | Fast single-pass review of your uncommitted changes: logic, security, data/state, error handling, performance, breaking changes. The everyday one — no subagents, so it's cheap. |
| `/review-deep` | Skill | Deep multi-agent review of the local working tree. Spawns 4 parallel reviewers (dependency impact, race conditions & state safety, logic/security/tests, tenant isolation), cross-checks them, then sends skeptic agents to adversarially verify each contestable finding before anything reaches the report. |
| `/review-plan` | Command | Critically reviews a plan *before* you implement it: challenges assumptions against the actual code, audits failure paths, checks blast radius, greps the repo's own `CLAUDE.md` for rules the plan touches, audits fault attribution, plays devil's advocate, ends with a Go / Adjust / Rethink verdict. |
| `/loopit` | Skill | Autonomous delivery runner. You write a task checklist; it takes each task through plan → `/review-plan` → implement → verify → review → fix every finding → re-verify → commit → push → client note → tick the box, one at a time, pausing only for genuine product decisions. Nothing is hardcoded to a project — branch rule, verify commands, commit style are all derived from the target repo. |
| `/loopable` | Skill | Finds recurring work worth automating, then ships the top candidate end-to-end. Mines git history, manual scripts, Claude usage and docs for chores with a rhythm; scores them on frequency/determinism/verifiability/blast-radius; maps each to one mechanism (`/loop`, `/schedule`, hook, cron, workflow, or plain script). Then runs the full delivery flow on the winner. |
| `/init-agents` | Skill | Scaffolds a tailored **agent team** into the current repo: detects the stack (JS/TS, PHP, Python, Go, Rust — monorepos too), then writes specialized subagents (`.claude/agents/`), pipeline commands like `/feature` and `/fix`, quality hooks, and a documented `CLAUDE.md` section. `minimal`/`full` tiers, project or user scope, clean `uninstall`. |
| `/explain-dev` | Command | Turns what you shipped into a structured, jargon-free client update (numbered points + a "how to test" section), ready to paste into WhatsApp/Slack. English or French. |
| `/vulgarize` | Skill | Same job, casual flowing text instead of a template — reads the diff itself. English or French. |
| `/sessions` | Skill | Lists your recent Claude Code sessions with the exact `claude --resume <id>` command for each. For after a reboot, or "where was that thing I did Tuesday?". |
| `/skill-stats` | Command | Leaderboard of which of these you actually use, from a durable usage log that survives transcript cleanup. |

Plus four hooks in `hooks/`: the two gates, the usage logger they read, and a status line showing `branch | N dirty | reviewed / UNREVIEWED` so you see the gate's verdict before it blocks you.

### Why multi-agent review?

A single-pass review is biased toward confirming its own findings and misses cross-file breakage. `/review-deep` splits the review across agents with *different* focuses, then flips the bias: fresh skeptic agents are prompted to **refute** each finding, and only findings that survive reach you — each with a confidence level. It sizes itself to the diff, so a 3-line change doesn't spawn 12 agents.

## Install

```bash
git clone https://github.com/Jewgah/claude-code-skills.git
cd claude-code-skills
./install.sh          # needs jq
```

The script copies skills to `~/.claude/skills/`, commands to `~/.claude/commands/`, hooks to `~/.claude/hooks/`, and **merges the hook wiring into `~/.claude/settings.json`** (backed up first, idempotent, skips anything you already have). It only claims `statusLine` if you don't already have one.

Then start a **new** Claude Code session.

Prefer to have Claude do it? Paste [`ONBOARDING-PROMPT.md`](ONBOARDING-PROMPT.md) into Claude Code in this folder — it inspects before installing, runs the test suite, then helps you write the per-repo `CLAUDE.md` files that make the reviews actually smart. New to all this? Read [`CHEATSHEET.md`](CHEATSHEET.md) — one line per command, plain words.

## Usage

```
/review                     # all uncommitted changes  (also: staged | unstaged | last-commit)
/review-deep                # the deep multi-agent one (also: staged | last-commit | branch)
/review-plan                # the active plan-mode plan, or the approach in your last message

/loopit                     # run ./loop-tasks.md to completion, one task at a time
/loopit FX-02               # run a single task from the queue

/loopable                   # find the top recurring chore and ship its automation
/loopable scan              # diagnose-only: rank candidates, build nothing

/init-agents                # scaffold an agent team into this repo (also: full | uninstall)
/explain-dev en             # client update for what you just shipped (or: fr)
/vulgarize en               # the casual version (or: fr)
/sessions                   # recent sessions + resume commands
/skill-stats                # what you actually use, ranked
```

### The loop

`/loopit` is the "go make all of this happen" mode. Write a checklist:

```markdown
- [ ] FX-01 | . | Empty dashboard shows a blank card — show a "Create your first project" CTA
- [ ] FX-02 | ../api | Rate-limit /signup — 5/min per IP, 429 with Retry-After
```

`- [ ]` pending, `[x]` done, `[~]` blocked. Then run `/loopit`. Per task it plans, reviews the plan, implements, runs the repo's own verify commands, reviews the diff, fixes **every** finding, re-verifies, commits by explicit path, pushes per the repo's branch rule, writes a plain-language change note, and moves on.

**Project-specific rules belong in that repo's `CLAUDE.md`, not in the skill.** That file is also what lifts `/review-plan` and `/review-deep` from generic bug-hunting to catching *your* mistakes.

## How the gates work

**Plan gate** — stateless. The hook denies `ExitPlanMode` and tells Claude to run `/review-plan`, then re-submit the plan ending with `<!-- plan-reviewed -->`. That marker is the only thing that lets a plan through, so there's no flag file to go stale and no loop. Tell Claude to skip the review and it just appends the marker.

**Commit gate** — the `log-skill.sh` hooks append one line per skill use (`timestamp ⇥ skill ⇥ typed|nl ⇥ cwd`) to `~/.claude/skill-usage.log`. The gate asks that log one question: *did a review run in this repo since the last commit?* If not, the commit is denied with instructions on which depth to use. The model picks `review` vs `review-deep` by blast radius — the hook only enforces that **something** ran.

### Known edges (all verified by the test suite)

- **Bypassing one trivial commit**: `touch ~/.claude/.skip-commit-review`, then commit. It must be a **separate step** — the hook inspects the command before it runs, so `touch … && git commit` is still denied. The marker is consumed on use.
- **Blind spot**: a commit buried inside a script (`bash deploy.sh`) isn't seen — the hook reads the command string, not the script.
- `git commit-tree` is denied too (substring match). Rare, and the message tells you the way out.
- Missing `jq` fails **closed** (denies with an explanation) rather than silently disabling itself.
- Repo paths are matched both physically and logically, so a repo under a symlinked path (`/tmp`, `/var`, a symlinked projects dir) never gets stuck permanently denied.

```bash
bash test/run-hooks.sh                      # 22 assertions against this repo's copies
HOOKS=~/.claude/hooks bash test/run-hooks.sh # …or against the ones you installed
```

Temp dirs and a fake `HOME` — it touches nothing of yours.

## Requirements

- `jq` — the commit gate and the installer
- `node` — the plan gate
- `python3` — `/sessions` only
- `/review-deep`, `/loopit` and `/loopable` spawn subagents, so they cost real tokens. Use `/review` for everyday work and keep the deep ones for changes that scare you.

## License

[MIT](LICENSE)
