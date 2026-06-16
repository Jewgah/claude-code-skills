# claude-code-skills

Battle-tested [Claude Code](https://claude.com/claude-code) skills and slash commands for shipping safely — a deep multi-agent code review, an adversarial plan review, and a scaffolder that installs a tailored agent team into any repo.

## What's inside

| Command | Type | What it does |
|---------|------|--------------|
| `/review-deep` | Skill | Deep multi-agent code review of your local working tree. Spawns 4 parallel reviewer agents (dependency impact, race conditions & state safety, logic/security/tests, tenant isolation), cross-checks their findings, then sends skeptic agents to adversarially verify each contestable finding before anything reaches the report. |
| `/review-plan` | Slash command | Critically reviews a plan/approach *before* you implement it: challenges assumptions against the actual code, audits failure paths, checks blast radius, lists what the plan *doesn't* mention, plays devil's advocate, and ends with a Go / Adjust / Rethink verdict. |
| `/init-agents` | Skill | Scaffolds a tailored Claude Code **agent team** into the current repo: detects the stack (JS/TS, PHP, Python, Go, Rust — monorepos too), then proposes and writes specialized subagents (`.claude/agents/`), pipeline commands like `/feature` and `/fix` (`.claude/commands/`), quality hooks (format-on-edit, guard), and a documented `CLAUDE.md` section. Everything is committed to git so the whole team gets it. Supports `minimal`/`full` tiers, project or user scope, and clean `uninstall`. |
| `/loopable` | Skill | Finds recurring work worth automating, then ships the top candidate end-to-end. Mines git history, manual scripts, Claude usage, and docs for chores with a rhythm; scores them on frequency/determinism/verifiability/blast-radius; maps each to one mechanism (`/loop`, `/schedule`, hook, cron, workflow, or plain script). Then takes the winner through the full delivery flow — plan → `/review-plan` → implement → `/review-deep` → fix every finding → commit → write a ticket. Gates deploys/pushes/DB changes behind explicit consent. |

### Why multi-agent review?

A single-pass review is biased toward confirming its own findings and misses cross-file breakage. `/review-deep` splits the review across agents with *different* focuses, then flips the bias: fresh skeptic agents are prompted to **refute** each finding, and only findings that survive reach you — each with a confidence level. It also sizes itself to the diff, so a 3-line change doesn't spawn 12 agents.

## Install

```bash
git clone https://github.com/Jewgah/claude-code-skills.git
cd claude-code-skills
./install.sh
```

The script copies skills to `~/.claude/skills/` and commands to `~/.claude/commands/`, skipping anything you already have. Prefer manual? Skills are folders (`cp -r skills/<name> ~/.claude/skills/`), commands are single files (`cp commands/<name>.md ~/.claude/commands/`).

Start a new Claude Code session — they show up as slash commands.

## Usage

```
/review-deep                # review all uncommitted changes
/review-deep staged         # only staged changes
/review-deep last-commit    # the last commit
/review-deep branch         # whole branch vs its base

/review-plan                # review the active plan-mode plan or last proposed approach
/review-plan <paste plan>   # review a specific plan/approach

/init-agents                # scaffold an agent team into the current repo (minimal tier)
/init-agents full           # full tier: more agents, pipeline commands, hooks
/init-agents uninstall      # cleanly remove what it installed

/loopable                   # find the top recurring chore and ship its automation end-to-end
/loopable scan              # diagnose-only: rank candidates, build nothing
/loopable "#2"              # build the #2 candidate from the last ranked table
/loopable releases          # focus the scan on a given area
```

**When to use which:** `/review-plan` before you write code; `/review-deep` before a risky change ships; `/loopable` when you suspect you're doing the same chore by hand on a rhythm and want it automated. For a fast everyday pre-commit pass, a plain single-pass review is enough — those reviews are the heavy artillery.

No external dependencies — all work with stock Claude Code (`/review-deep` uses the built-in Explore agent type). `/loopable` composes `/review-plan` and `/review-deep`, which ship in this repo.

## License

[MIT](LICENSE)
