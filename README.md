# claude-code-skills

Battle-tested [Claude Code](https://claude.com/claude-code) skills and slash commands for reviewing work **before** it ships — a deep multi-agent code review, and an adversarial plan review.

## What's inside

| Command | Type | What it does |
|---------|------|--------------|
| `/review-deep` | Skill | Deep multi-agent code review of your local working tree. Spawns 4 parallel reviewer agents (dependency impact, race conditions & state safety, logic/security/tests, tenant isolation), cross-checks their findings, then sends skeptic agents to adversarially verify each contestable finding before anything reaches the report. |
| `/review-plan` | Slash command | Critically reviews a plan/approach *before* you implement it: challenges assumptions against the actual code, audits failure paths, checks blast radius, lists what the plan *doesn't* mention, plays devil's advocate, and ends with a Go / Adjust / Rethink verdict. |

### Why multi-agent review?

A single-pass review is biased toward confirming its own findings and misses cross-file breakage. `/review-deep` splits the review across agents with *different* focuses, then flips the bias: fresh skeptic agents are prompted to **refute** each finding, and only findings that survive reach you — each with a confidence level. It also sizes itself to the diff, so a 3-line change doesn't spawn 12 agents.

## Install

```bash
git clone https://github.com/Jewgah/claude-code-skills.git
cd claude-code-skills

# review-deep (a skill — folder goes under ~/.claude/skills/)
mkdir -p ~/.claude/skills
cp -r skills/review-deep ~/.claude/skills/

# review-plan (a slash command — single file under ~/.claude/commands/)
mkdir -p ~/.claude/commands
cp commands/review-plan.md ~/.claude/commands/
```

Start a new Claude Code session — they show up as `/review-deep` and `/review-plan`.

## Usage

```
/review-deep                # review all uncommitted changes
/review-deep staged         # only staged changes
/review-deep last-commit    # the last commit
/review-deep branch         # whole branch vs its base
/review-plan                # review the active plan-mode plan or last proposed approach
/review-plan <paste plan>   # review a specific plan/approach
```

**When to use which:** `/review-plan` before you write code; `/review-deep` before a risky change ships. For a fast everyday pre-commit pass, a plain single-pass review is enough — these are the heavy artillery.

No dependencies — both work with stock Claude Code (`/review-deep` uses the built-in Explore agent type).

## License

[MIT](LICENSE)
