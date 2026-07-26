# What each thing does — in one line

## The two automatic gates (you don't call these, they just fire)

| | What it does |
|---|---|
| **Plan gate** | Claude can't show you a plan until it has criticised its own plan first. |
| **Commit gate** | Claude can't commit until it has reviewed the code since your last commit. |

That's the whole idea: the two steps everyone skips when they're in a hurry become impossible to
skip. Everything else in the kit is either what those gates run, or a tool that reuses their data.

**Escape hatches** — because a gate you can't bypass is a gate you'll rip out:
- Plan: tell Claude "skip the plan review".
- Commit: run `touch ~/.claude/.skip-commit-review`, **then** commit (two separate steps).

## The commands you type

| Command | In plain words | Reach for it when |
|---|---|---|
| `/review` | One careful read of your uncommitted changes: bugs, security, edge cases. Fast, cheap. | Everyday changes, before committing. |
| `/review-deep` | Sends 4 reviewers at your diff from different angles, then sends *skeptics* to disprove what they found, so you only see findings that survived. Slower, costs more. | The change that scares you: money, auth, data, migrations, shared code. |
| `/review-plan` | Attacks a plan *before* you build it: what is it assuming, what breaks, what did it forget, is there a simpler way. Ends with Go / Adjust / Rethink. | Any plan bigger than a one-liner. Runs automatically in plan mode. |
| `/loopit` | You write a checklist of tasks; it does all of them, one at a time, start to finish, without asking permission between tasks. | You have 5 small chores and don't want to babysit each one. |
| `/loopable` | Looks at your repo and history and tells you which recurring chore is worth automating, then builds the top one. | "I keep doing this by hand every week." |
| `/explain-dev` | Turns what you just built into a WhatsApp message a non-technical client actually understands, plus how they can test it. `en` or `fr`. | After shipping, when someone non-technical needs to be told. |
| `/vulgarize` | The same job as `/explain-dev`, but a casual flowing text message instead of a numbered template. Reads the diff itself. | Same moment, when the recipient is informal. |
| `/sessions` | Lists your recent Claude Code conversations with the exact command to resume each one. | After a reboot, or "where was that thing I did Tuesday?" |
| `/skill-stats` | Ranks which of these you actually use. | Every month or so, to prune what you never touch. |

## How `/loopit` works in practice

Write a file called `loop-tasks.md`:

```markdown
- [ ] T1 | . | Empty dashboard shows a blank card — show a "Create your first project" button instead
- [ ] T2 | . | Signup has no rate limit — 5 per minute per IP, return 429
```

Run `/loopit`. For **each** task it plans it, criticises the plan, builds it, runs your tests,
reviews the diff, fixes every finding, re-runs the tests, commits, pushes, writes the client
message, ticks the box, and moves to the next one. It only stops to ask you when there's a real
product decision to make.

`- [ ]` = to do, `[x]` = done, `[~]` = blocked/needs your decision.

## The one thing that makes all of this smarter

A `CLAUDE.md` file at the root of each of your repos, saying what a newcomer couldn't guess: how it
deploys, which branch is dangerous, how to run the tests, the trap that already bit someone once.
`/review-plan`, `/review-deep` and `/loopit` all read it and hold you to it. Without it they only
catch generic mistakes; with it they catch *your* mistakes.

## Small print

- `/review-deep`, `/loopit` and `/loopable` spawn extra agents, so they cost noticeably more tokens
  than `/review`. Use the cheap one by default.
- The status line shows `branch | N dirty | reviewed / UNREVIEWED` so you can see the commit gate's
  verdict before you hit it.
- Everything above is plain markdown in `~/.claude/skills/` and `~/.claude/commands/`. Open any of
  them and edit the wording — they're instructions, not code.
