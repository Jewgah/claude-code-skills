---
name: loopit
description: Drive a task queue (loop-tasks.md) to completion in ANY repo. Detect the repo's own rules, then for each task a check-writer writes hidden acceptance checks, then plan -> /review-plan -> implement -> verify -> /review -> fix all findings -> /battle-test -> gate (the checks decide) -> commit -> push -> client doc -> mark done. Each task runs in its OWN subagent (context isolation, token-cheap); the main session only orchestrates. Autonomous between tasks; pauses only for genuine product decisions.
disable-model-invocation: true
argument-hint: "[tasks-file path (default ./loop-tasks.md), a single TASK-ID, plan:<path>, or stats]"
---

# Loopit: run a task queue through the full delivery flow

You are an **autonomous delivery runner**, project-agnostic. Input: `$ARGUMENTS`, a path to a
tasks file (default `./loop-tasks.md`), or a single `TASK-ID` to run only that task.

Process tasks **strictly one at a time, top to bottom**, each through the complete cycle below.
The loop is autonomous *between* tasks, so do not ask "should I continue" after each one. Pause only
at the explicit gates in "When to pause".
If this file comes back truncated after a compaction (the gate, Step 10 and the End report are near
the end), Read it in full before your next step.

**Nothing here is hardcoded to a specific project.** Every project-specific rule (branch, deploy,
commit style, client-doc format, post-push build) is **derived from the target repo** in Step 0,
primarily from its `CLAUDE.md` + recalled memories + its tooling files. If a repo needs a special
rule, it belongs in that repo's `CLAUDE.md`, not in this skill.

**Files beside this one**: `EXECUTOR.md` (the per-task cycle, read by each builder), `CHECKS.md`
(read by the check-writer), `FORK.md` (read only when a task forks), and the scripts
`run-checks.sh` (the gate), `drift.sh` (stale-doc finder), `stats.sh` (first-pass rate) with their
self-test `test-scripts.sh`. The scripts need `jq`.

## Inputs

- `$ARGUMENTS` empty -> read `./loop-tasks.md` in the current directory.
- `$ARGUMENTS` = a path -> use that tasks file.
- `$ARGUMENTS` = a `TASK-ID` (e.g. `FX-A03`) -> run only that task, then stop.
- `$ARGUMENTS` = `plan:<path>` -> **ad-hoc plan mode** on that plan file (see below).
- `$ARGUMENTS` = `stats` -> run `bash ~/.claude/skills/loopit/stats.sh`, print its output, stop.

The mode is **declared, never inferred**: some plan files contain `- [ ]` lines and some queue
files live under `~/.claude/plans/`, so neither the content nor the path tells them apart. The
caller knows which it is, so the caller says so.

The tasks file's directory anchors any relative `repo` paths (below).

## Tasks file format

A markdown checklist. Each line:

```
- [ ] TASK-ID | repo | Title - short description / acceptance / notes
```

- `[ ]` = pending, `[x]` = done, `[~]` = blocked (needs a decision; skip and report).
- `repo` = the working directory for the task. Resolve as: an **absolute path** as-is; a
  **relative path** against the tasks-file's directory; `.` or empty -> the current repo. Do NOT
  assume any fixed parent directory.
- Lines starting with `#` are section headers; ignore for processing.
- A task line may be followed by indented grounding notes, one per line, starting with two
  spaces and `> ` (attachment digests, decisions from a ticket's comments, and similar). They
  belong to the task above and are passed VERBATIM to that task's subagent as Extra
  grounding; they are not tasks.
- A `{tasks-file-stem}-run.md` beside the tasks file (`loop-tasks.md` pairs with
  `loop-tasks-run.md`) is the run log: append-only OUTPUT, written by the orchestrator in
  Step 10. It is never read as input and never passed to a subagent as grounding, so a
  task's own report can never be fed back into a re-run of that task.
- A task tagged `(decision)` in its notes needs product input, see "When to pause".
- A task tagged `(tier: fast)` in its notes asks for the cheap model (see the Execution model's
  ladder). It only ever forces the tier DOWN, and never past the client-repo, opt-out or
  new-test rungs, so tagging a migration `(tier: fast)` changes nothing.
- A task tagged `(fork)` forks from its first dispatch (see `FORK.md`).

## Ad-hoc plan mode (one approved plan, no queue)

Entered only via `$ARGUMENTS` = `plan:<path>`. The unit of work is the plan file, not a task
line: there is no queue, no checkbox, no tasks file.

- **Repo = cwd.** If the plan names a repo other than the cwd, or spans several, do not guess:
  that is the "genuine ambiguity about the target" case in "When to pause". Confirm once, then
  run.
- **Skip Steps 1 and 2.** The user approved this plan (and, with the plan-review gate hook
  installed, it went through `/review-plan` before it could be presented); re-planning burns the
  reviewer on settled work and lets the subagent drift from what was approved. Pass the plan
  file's content VERBATIM to the subagent as its spec and start at Step 3.
- The check-writer still runs first, with the plan content in place of the task line: the
  approved plan is the spec it writes the acceptance checks against.
- Still ONE builder subagent, for the same context-isolation reason as a queue task.
- The TASK-ID is the plan file's stem (check folder, stats line).
- Run Steps 3 to 6, the gate, then Steps 6b to 9b, then the End report. Step 10 writes only the
  stats line: nothing to flip and **no run log**: a single task's report is still in context when
  the report is written. Assemble the End report from the subagent's report directly.
- **If the cwd is not a repo, Step 0's no-repo rule wins over the line above**: Steps 3 to 6
  and the gate only, nothing committed. Config work under `~/.claude` is both, so this is the normal case.

## Step 0 - Detect the project's rules (do this first, per repo involved)

Before running tasks, `cd` into the repo and establish its rules **from the repo itself**, never
assume. Read its `CLAUDE.md` + recalled memories, inspect git, and detect tooling:

- **No repo at all**: if `git rev-parse --show-toplevel` fails, there is nothing to commit to.
  Run Steps 3 to 6 (implement, verify, review, blind-spot, battle-test) and the gate, skip Steps
  7 to 9b, and say plainly in the End report that nothing was committed and why (config work under
  `~/.claude` runs from a non-repo cwd; the commit-review gate exits 0 outside a repo).
- **Repo + git**: `git rev-parse --show-toplevel`, `git branch --show-current` (empty -> detached
  HEAD; see Step 8), the default branch (`git symbolic-ref --quiet --short
  refs/remotes/origin/HEAD`), and the push remote (`origin` if present, else the repo's single
  remote, and if several and none is `origin`, ask). **Re-run this detection for each distinct repo
  in the queue**, rules are per-repo.
- **Branch & push rule** (safety-critical, get this right before any push):
  1. If `CLAUDE.md`/memory states a rule ("push `dev`, a gate promotes `main`"; "never push
     `main`"), use it.
  2. Else look for an IMPLICIT rule: scan `.github/workflows/*.y*ml` + any pre-push hook for a
     protected/promote/green-gate pattern (e.g. a workflow on push to `dev`/`develop`/`staging`
     that fast-forwards `main`) and infer the push branch from it.
  3. Else default to **push the current branch**, UNLESS the current branch IS the
     default/production branch (`main`/`master`) AND a non-production sibling
     (`dev`/`develop`/`staging`) exists: then do NOT auto-push to production, PAUSE and confirm
     the target (the guardrail for repos whose "never push prod" rule lives only in CI config).
  Never switch or guess a branch; honor any "never push X" guardrail (documented or inferred).
- **Verify commands**: detect what the repo actually has: `package.json` scripts
  (`typecheck`/`lint`/`test`/`build`), `composer.json` scripts (`cs`/`test`), a `Makefile`,
  `cargo`/`go`/`pytest`, etc. Run the ones that exist. If a change is a single language file and no
  suite covers it, fall back to the language's own check (e.g. `php -l`, `tsc --noEmit`) plus a
  minimal runnable assertion. These commands are the cheap Step 4 gate; the deeper pre-push gate
  (Step 6) delegates detection to `/battle-test`, so do not duplicate that work here.
- **has_runner**: yes when a test command was found above, or the repo has a `docker-compose*.y*ml`
  / `compose.y*ml` for a local stack. No means the check-writer is skipped (see "The check-writer
  and the gate").
- **Review skill**: `/review` by default; use `/review-deep` if `CLAUDE.md`/memory calls for a
  deeper per-commit review.
- **Commit convention**: match the repo's existing `git log` style (Conventional Commits, a
  `prefix:` style, etc.). Default to Conventional Commits if the log is mixed/empty.
- **Client-doc convention**: how this repo produces the human-facing change note: `/explain-dev`
  (no argument gives English; call it as `/explain-dev fr` for French), or none. **Language is
  ENGLISH by default**, and stays English unless the repo's `CLAUDE.md`
  explicitly says otherwise. Output goes to ONE per-product folder under `~/Downloads/loopit/{projectname}/`.
- **Post-push build/deploy**: does reaching users need a separate step after push (a mobile build,
  a manual deploy)? Check `CLAUDE.md` (a "Build"/"Deploy"/"Release" section) and tell-tale config
  (`app.json`/`eas.json` -> EAS; a deploy script). If the command is documented, note it for the
  after-run step; if a build is clearly needed but the command isn't documented, ASK before
  running it (don't guess platform/profile).

**State the resolved rules in one line before the first task** (branch/push, verify cmds, review
skill, client-doc target) so the run is transparent.

## Step 0b - Re-check every blocked task before saying the queue is empty

A `[~]` line is a claim written on the day it blocked, never re-read afterwards. A real case: a task
sat `[~]` "not assigned to me" for five days after it WAS assigned and its dependency had shipped,
so the queue looked empty while runnable work waited. So before the first task, and before any
"nothing to run" verdict, read every `[~]` line in the tasks file and test each blocker that a tool
can check:

- **needs TASK-ID**: shipped when that task is `[x]` in this file.
- **needs commit / PR X**: shipped when the named commit is on the default branch, or the PR is
  merged.
- **needs ticket X / assigned to me / ticket status**: when this session has a tool for your issue
  tracker (an MCP server, a CLI such as `gh`), read the ticket's status and assignee from it.

When every blocker on a line is checkable and now clear, flip it to `[ ]`, rewrite its stale
`blocked:` clause to `(unblocked {DD-Mon}: {what cleared})`, and run it in this queue. A line with
even one human blocker (a ruling, a client answer, a physical device) stays `[~]`. List both groups
in the start line: `Re-checked N blocked: reopened {ids}; still blocked {id: who}`.

When marking a task `[~]` from here on, write the blocker in the checkable words above, and name the
person for a ruling (`blocked: ruling, <who>: ...`), so the next run can re-test it.

## Execution model: one subagent per task (context isolation)

Why: in a single session, task #8 pays to re-read everything tasks #1-7 put in context
(file reads, review output, battle-test logs) on every message. Cache reads are most of a
loop's token bill. A per-task subagent starts clean, runs the whole cycle, and only its
short report enters this session.

Roles:

- **Orchestrator** (this session): Step 0 once per repo, owns the tasks file, then per task:
  check-writer, red run, builder, gate, Step 10, next task. Strictly sequential, never parallel
  (tasks may touch the same files and commits must stay ordered). The one exception is WITHIN a
  task: "Fork on hard tasks" (`FORK.md`) runs 2 builders in separate worktrees, and only one of
  them lands. Its three triggers: a standard-tier builder failing gate round 2, a standard-tier
  builder blocked for a TECHNICAL reason, a `(fork)` tag in the task's notes (forks from the first
  dispatch). On any of them, read `~/.claude/skills/loopit/FORK.md` first, never fork from memory.
- **Check-writer** (one per task, see "The check-writer and the gate"): writes the task's
  acceptance checks BEFORE the code, outside the repo, and returns only their intents.
- **Task subagent, the builder** (Agent tool, `subagent_type: general-purpose`, one per task):
  executes Steps 1 to 6 for its ONE task and returns `STATUS: ready` without committing; on the
  orchestrator's GO it finishes Steps 6b to 9b and returns the report below. It never sees the
  checks. Exception: if you are ALREADY a subagent, execute the cycle inline instead of nesting
  (no check-writer and no gate in inline mode: say so in the report).

**Every dispatch names its `model` explicitly. Never inherit, never omit it.** An omitted model
inherits the session's, which may be a premium-priced model you do not need for routine delivery.
Two tiers: **standard** (`opus`) and **fast** (`sonnet`); substitute your own if your plan names
them differently. Pick with this ladder and state which rung applied:

1. **Client repo, or a repo you cannot classify: standard.** Client repo means
   `git remote get-url origin` matches a line of `~/.claude/client-orgs.txt` (one org or owner per
   line; create it if you want the fast tier at all). No origin, no such file, or a check that
   cannot run: standard. The fast tier is an exception and defaults closed.
2. **Repo whose `CLAUDE.md` says `loopit: no fast tier`: standard.** The opt-out for a repo that
   is client-facing without being a client repo by origin.
3. **A task that creates a NEW test asserting against a fake, a mock, a scan or a derived
   list: standard**, whatever its tier tag. Enforced from BOTH ends, because a task line often
   does not reveal it: pick standard when the task obviously implies such a test, and
   `EXECUTOR.md` Step 5 requires a fast-tier subagent that discovers mid-task that it needs one to
   return `STATUS: escalate` before writing it. The mutation proof is self-attested and no hook
   checks it.
4. **Otherwise: fast.** Copy and wording, a config value, a rename, a field that follows an
   existing pattern already in the codebase, docs, and ordinary feature work. A `(tier: fast)` tag
   forces this rung, but never past rungs 1 to 3. Judge the rung on its first-pass rate against
   the standard tier's (`/loopit stats`) before trusting it with more.

**Escalation, not a gamble.** Re-dispatch the SAME task at the standard tier when a fast-tier
subagent returns `STATUS: escalate`, `STATUS: blocked`, a CRITICAL it could not resolve, or a suite
red twice. A wasted fast attempt costs a fraction of the standard run.

Dispatch prompt template (fill the {braces}; keep it self-contained, the subagent sees
nothing of this session):

    You are executing ONE task from a /loopit queue. Read
    ~/.claude/skills/loopit/EXECUTOR.md and execute Steps 1 to 6 for the single task
    below, then STOP with STATUS: ready and nothing committed. The orchestrator runs
    the acceptance checks and answers through a message: GO (then Steps 6b to 9b) or
    FAIL (then fix, Steps 4 to 6 again, ready again). Do not touch the tasks file or
    the run log (orchestrator's job). Never create a file named `loopit-*` in the
    repo: that prefix is reserved for the acceptance checks.

    Repo mode: {git | no-repo (ready after Step 6; on GO report shipped-uncommitted, nothing to commit to)}
    Tier: {fast | standard}
    Attempt: {n}/3
    Baseline HEAD: {the sha before this task's FIRST dispatch, or - in no-repo mode}
    Handoff note path: {tasks-file-stem}-handoff-{TASK-ID}.md, beside the tasks file
     (beside the plan as {plan-stem}-handoff.md in ad-hoc mode)

    Resolved repo rules (Step 0 already done, do not redo):
    {resolved rules: repo path, branch/push rule, verify cmds, review skill,
     commit convention, client-doc skill + language}

    Task line (verbatim):
    {task line}
    Extra grounding: {the task's indented > notes from the tasks file, verbatim, or "none"}

    Intents (the acceptance contract; you will NOT see the checks that enforce it):
    {the check-writer's INTENTS lines verbatim, or "none: {reason}"}
    EXISTS: {the check-writer's table, "adds nothing", or "not done: do the Step 1 lookup yourself"}

    Client doc goes to ~/Downloads/loopit/{productname}/ with filename prefix {NN}-.
    Manual steps (Step 9b) go on your report's MANUAL-STEPS line in full, never in a
    file. If this commit needs nothing from a human, write "none needed". Use `- [!]`
    instead of `- [ ]` ONLY for a step whose absence means something already deployed
    is broken, unsafe, or silently doing nothing right now; quote any such entry in
    full on the BLOCKER line, because it stops the queue.

    You cannot ask the user anything. On a "When to pause" gate (product decision,
    scope-changing CRITICAL, risky push target): STOP and return a blocked report,
    never guess. If your setup gates pushes and the push is denied: leave the commit
    local and report push-pending-consent; the orchestrator handles the push.

    Runaway guard, and it is a HANDOFF, not a failure: if you pass ~60 tool calls
    without converging, or the suite is red twice for the same cause, stop and hand
    off instead of grinding. Your context is the most expensive thing in this run and
    it only grows. Write the note to the Handoff note path above FIRST, then return
    STATUS: handoff. Leave the working tree exactly as it is; the successor continues
    from it. The Attempt field above says which try this is: on attempt 3, return
    blocked instead of handing off, because three fresh contexts that did not
    converge is a decision, not a fourth agent.

    At the end of Step 6, write the handoff note (short: what is built, files touched,
    how you verified it) and return ONLY:
    STATUS: ready | blocked | escalate | handoff | check-dispute
    HANDOFF: {the note path}
    SUMMARY: {one line: what you built}
    DISPUTE: {only on check-dispute: which intent, and why it is wrong or unachievable}
    PLAN / BLOCKED-ON: {only on escalate / blocked}

    After GO, end with EXACTLY this report block:
    STATUS: shipped | shipped-uncommitted | blocked | push-pending-consent | escalate | handoff
    HANDOFF: {path to the note, only if handoff. The note holds: what shipped, what
    remains, files touched, the exact next step, ATTEMPT n/3, RED-CAUSES (each cause
    seen red, verbatim), and MUTATION-PROOFS so far. The agent that observed a test
    go red is not the one that will file the final report.}
    COMMIT: {sha or -, and always - in no-repo mode}
    BATTLE-TEST: manual: {the checks /battle-test could not run, or -}
    HOW-TO-TEST: {how a person tests this on staging (a build, for mobile): the URL, which
    account (a test account when one exists, never a client's real one), then numbered steps,
    each with its expected result. Continuation lines indented. "-" only for a change nobody
    can see (docs, config).}
    MUTATION-PROOFS: {for every NEW test asserting against a fake, mock, scan or derived
    list: the mutation you applied and the NAME of the test that went red, quoted from the
    runner. "none needed" ONLY when every new test exercises a pure function with real
    inputs. A test never seen red has not been shown to test anything.}
    TRIM: {Step 5c, both halves required. What you cut as over-engineering and why,
    or "nothing cut"; then every change that narrows or alters behaviour that already
    worked, with whether a test covers it, or "nothing narrowed". Silence is not an
    answer: an unanswered TRIM is treated as a skipped step.}
    CHECK-LOGGING: {Step 5d: gaps found, fixed, deliberately left and why; or
    "n/a (repo has no check-logging skill)".}
    CLIENT-DOC: {path or -}
    MANUAL-STEPS: {every `- [!]` / `- [ ]` entry for this commit, written out in full, or
    "none needed"}
    BLOCKER: {any `- [!]` entry written this task, quoted in full, or "none". The
    orchestrator pauses the queue on this line and shows it to the user verbatim.}
    DRIFT: {Step 6b: hits confirmed stale and fixed in this commit, hits left and why, or
    "none"}
    DEFERRED: {follow-ups or -}
    RECORD-CORRECTIONS: {claims in the tasks file or the repo's docs the work invalidated, or -}
    MEMORY-FIX: {one line per memory or ~/.claude/CLAUDE.md claim the work invalidated:
    `file | exact old text | new text`, or -. You never edit those files yourself.}
    In RECORD-CORRECTIONS and MEMORY-FIX a count or a measurement is always written with
    the query or command that produced it and the date, never as a bare number.
    ASSUMPTION-AUDIT: {each load-bearing claim in this report marked VERIFIED (naming the
    check you ran in your session) or ASSUMED (naming the source and why it could not be
    verified). MANDATORY - a report without it is incomplete. Never mark VERIFIED without
    having run the check.}
    BLOCKED-ON: {exact decision needed, only if blocked}

Orchestrator, after each final report: append the `CHECKS:` line, then run Step 10 from it (log,
stats line, flip checkbox, apply RECORD-CORRECTIONS). On push-pending-consent: ask the user, then
perform whatever your setup's push gate requires as its OWN step and push again from here. On
blocked: mark `[~]` and ask or skip-and-report per the run. The orchestrator assigns
each dispatch its `NN-` client-doc prefix so subagents never race on numbering.
Spot-check each reported CLIENT-DOC file with `head -1` (not a full read, you do this
once per task): its first line must match the `*Update delivered` / `*Update planned`
template; anything else (headers, SHAs, wrapper prose) gets fixed before the next
dispatch - format drift is the observed failure mode. `CLIENT-DOC: -` is not a
failure and has nothing to check: it is the normal report on a repo with no client doc,
and on any no-repo run.

### The check-writer and the gate

The builder never judges its own work: a separate agent writes the acceptance checks first, a script
runs them after `ready`, exit codes decide. The builder sees only the intents.

Per task, after noting Baseline HEAD, `cd {repo}` as its own Bash call and stay there until the
task's final report: a subagent's hooks see this session's cwd, so a builder's `/review` logged from
elsewhere never satisfies the commit-review gate. A repo in a temp or scratchpad folder cannot hold
the cwd: run that queue from a session opened in the repo.

0. **Mark the task as running, BEFORE any dispatch**: `mkdir -p
   ~/.claude/loopit-checks/{repo-basename}-{crc}/{TASK-ID} && touch
   ~/.claude/loopit-checks/{repo-basename}-{crc}/{TASK-ID}/dispatched` (same crc as below). A
   dashboard or a parallel session can read "running" from this folder's mtimes.
1. **Check-writer.** Skipped when Step 0 says `has_runner: no`: then `CHECKS: 0 (no runner)` and
   `EXISTS: not done` for the builder. Otherwise Agent tool, `subagent_type: general-purpose`,
   standard tier always, outside the ladder (its context is tiny and the quality of the check is
   the whole point), prompt:
   "Read ~/.claude/skills/loopit/CHECKS.md and do exactly that for the task below. Repo:
   {path} ({git | no-repo}). Resolved rules: {Step 0 rules}. Output folder:
   ~/.claude/loopit-checks/{repo-basename}-{crc}/{TASK-ID}/ (crc: `printf %s {repo root} | cksum |
   cut -d' ' -f1`). Task line (verbatim): {task line}. Extra grounding: {> notes or none}."
   (Ad-hoc plan mode: the plan content replaces the task line.)
2. **Clean tree (git mode), then the red run**, from its `MANIFEST:` line:
   `bash ~/.claude/skills/loopit/run-checks.sh {manifest} red {repo | -}`. Run every run-checks.sh
   call with the Bash `timeout: 600000`; read its stdout, never a log in full. `RESULT red-ok`: keep
   its `HASH` line, dispatch the builder. `RESULT none`: dispatch it. `red-bad`, `collision` or
   `invalid`: re-dispatch the check-writer ONCE with those lines. A second failure, a second death,
   or a dirty tree it left (stash as `loopit-checkwriter-{TASK-ID}`, name it in the End report):
   the task runs WITHOUT a gate, `CHECKS: 0 (check-writer failed)`, `EXISTS:` from its report if any.
3. **Builder** dispatch with the check-writer's `INTENTS:` and `EXISTS:` lines. Never a path under
   `loopit-checks`, never a check command, never test code.
4. **Gate**, on `STATUS: ready`: `run-checks.sh {manifest} green {repo | -} {HASH}`. Resume the
   builder with SendMessage (the agentId from its dispatch):
   - `green-ok`, or the task has no checks: in git mode first run
     `bash ~/.claude/skills/loopit/drift.sh {repo} {Baseline HEAD}` (information, never a gate), then
     "GO. Commit these check files with the task: {the INSTALLED paths, or none}. Drift: {drift.sh
     output verbatim}." It returns its final report. A task that reached `green-ok` is never gated
     again: a successor gets GO with the same INSTALLED paths.
   - `green-fail` or `collision`: "FAIL, gate round {r}/3. {the FAIL / COLLISION lines}. First
     error lines: {`grep -nEi 'error|fail|expected|assert' {manifest dir}/green-{i}.log | head -20 |
     sed "s#$HOME/.claude/loopit-checks[^ :]*#<check>#g"` for each failing check}. Fix, re-run
     Steps 4 to 6, return ready." Round 2 failing on a standard-tier builder: **Fork** instead of
     round 3: read `~/.claude/skills/loopit/FORK.md` first, never fork from memory.
     After round 3 fails (or the fork finds no winner): `[~]` blocked, the work stashed as
     `loopit-{TASK-ID}` per the clean-tree rule below.
   - `tampered` (a check changed since the red run) or `STATUS: check-dispute`: `[~]` blocked, the
     work stashed, the TAMPERED or DISPUTE line shown to the user. No new check-writer.
   - `interrupted` or `invalid`: re-run once, then `[~]` blocked.
   - SendMessage cannot reach the builder: dispatch a fresh one at Attempt n+1 with the handoff
     note it wrote at ready, under the handoff rules below.
   - **Every re-dispatch of the same task** (escalate, handoff, dead builder) carries the SAME
     intents, `EXISTS`, manifest, HASH and round count. One check-writer per task, plus one retry.
5. **After a final report with a COMMIT sha** (git mode, checks installed): `run-checks.sh {manifest}
   committed {repo} {COMMIT} {HASH}`; `tampered` is shown to the user too. `committed-diff` means a
   check was weakened after GO: show the user before the next task. Then append `CHECKS: {n}, red
   {red-ok | none | failed}, gate rounds {r}, disputes {d}, first-pass {yes | no | -}`: `yes` only
   when round 1 was `green-ok`; `-` with no checks.

### Handling a `STATUS: handoff`

A task subagent that stopped before finishing, deliberately, to avoid dragging a fat context
through more turns. Runaway subagents are where most of a loop's tokens go.

- **The note is a FILE, and you give the subagent its path in the dispatch.**
  `{tasks-file-stem}-handoff-{TASK-ID}.md` beside the tasks file; in ad-hoc plan mode there is no
  tasks file, so it goes beside the plan as `{plan-stem}-handoff.md`. In no-repo mode there is no
  HEAD to compare and no porcelain to read, so the note and the working tree are the only ground
  truth.
- **Do NOT apply the clean-tree rule here.** "Leftovers get stashed" would stash exactly the
  work the successor must continue. The tree IS the handoff. Do not stash, do not commit it.
- **Re-dispatch the SAME task immediately**, same tier and model, passing the handoff note's
  path and `ATTEMPT: {n+1}/3`. The successor reads the note first, before anything else.
- **Carry the ORIGINAL pre-task HEAD** as the baseline for every dispatch of that task, never
  the HEAD as of the handoff. Re-baselining makes a later dead subagent read as "no new commit,
  mark `[~]`" on work that already shipped.
- The successor re-runs Steps 4 to 6 against the FULL accumulated diff, not its own increment:
  the commit-review gate only checks that some review is newer than the last commit and the newest
  pending edit; it cannot tell what that review saw, so a predecessor's review would otherwise
  green-light code nobody reviewed.
- **Attempt 3 returns blocked**, not a fourth handoff.

The ~60 tool-call threshold lives in the dispatch prompt and is weakly held: treat the handoff as
guidance that helps but does not bind, and do not claim the tail is capped.

### Dead or garbled subagents

Note the repo's HEAD (`git rev-parse HEAD`) before each dispatch. Dead or garbled subagent
(no parsable report): establish the truth from the repo, not from the report. A commit
newer than the noted HEAD means the task shipped (reconstruct the report fields from the
commit and the client-doc folder); no new commit means mark it `[~]` with what you found.
Exception, the clean death: no report, no new commit, clean tree means the subagent died
before doing anything (transient API failure). Re-dispatch the identical prompt ONCE;
only a second death marks the task `[~]`.
Either way the run log still gets its entry: a report reconstructed from the repo is logged
with `(reconstructed)` on its heading, and a task marked `[~]` is logged with what you
found and what it is blocked on. A log with holes is not one the End report can lean on.
And after EVERY report, dead or shipped: `git status --porcelain` must be clean before the
next dispatch. Complete leftovers belong in the task's commit, incomplete ones get stashed
and named in the End report.

## Concurrent loops (different repos only)

Several /loopit sessions in parallel are fine when each targets a DIFFERENT repo and tasks
file: the tasks file, the plans and verify logs (named `loopit-{repo-basename}-{crc}-{TASK-ID}`, since
task ids repeat across repos), the client-doc folders, the check folders (name + crc of the
repo root) and the commit-review gate are all per-repo, so they don't interact. Never point two
loops at the same tasks file (the checkbox flips and HEAD baselines would race); there is
deliberately no lock file - one loop per repo is the rule. If your setup gates pushes behind a
consent step, check that its state is per-repo rather than global before running loops in
parallel: a global marker lets two loops consume each other's consent. Either way, one consent per
push - ask each time.

## The cycle (per task)

Steps 1 to 9b execute INSIDE the per-task subagent and live in **`EXECUTOR.md`**, beside this
file. That is what the dispatch prompt points at and the only file a task subagent reads: half of
this file is orchestrator-only, and a subagent re-pays every byte it loads on every one of its
turns.

Change a step, change `EXECUTOR.md`. Change how tasks are dispatched, logged or reported, change
this file. Step 10 below is the orchestrator's and stays here.

### Step 10 - Mark done & loop (ORCHESTRATOR, from the subagent's report)
- **Append the report to the run log FIRST, before flipping anything.** Target
  `{tasks-file-stem}-run.md` beside the tasks file (`loop-tasks.md` logs to
  `loop-tasks-run.md`, `loop-tasks-sourcing.md` to `loop-tasks-sourcing-run.md`); never one
  shared log per directory, a repo commonly carries several queues side by side. Create it
  with a one-line header if absent, then APPEND only: never rewrite it, never delete an entry.
  One `## {TASK-ID} - {title} - {YYYY-MM-DD}` section per task, holding the subagent's report
  block verbatim. Track the file however the repo already tracks its tasks file (committed with
  the trackers, or ignored) so the loop adds no new git habit.
  Order matters: log, then flip. A crash between the two must leave the log AHEAD of the
  record, because an entry with no checkbox is a task you simply re-run, while a checkbox
  with no entry is data that is gone.
- **Stats line**, right after the log entry: `bash ~/.claude/skills/loopit/stats.sh add {YYYY-MM-DD}
  {repo basename} {TASK-ID} {model} {checks} {red} {rounds} {first-pass} {disputes} {status}`, from
  the `CHECKS:` line and the report: single tokens, whole numbers for the three counts. It refuses
  a malformed row (exit 4); fix the values, never skip the line.
- Flip the task's checkbox to `[x]` (or `[~]` if blocked) in the tasks file.
- **If the task carries an issue-tracker id** and this session has a tool for that tracker, move
  the issue to its review state on `STATUS: shipped`. That is the ONLY automatic post: the client
  doc is the user's to send. A failed move is logged and never blocks the queue.
- The report's ASSUMPTION-AUDIT field is a claim, not a fact: anything from it that reaches a
  human deliverable is re-verified at delivery time.
- **Reconcile the record with what you LEARNED, not only with what you shipped.** In the SAME edit,
  correct anything the tasks file or the repo's docs now contradict. **Never memory, never
  `~/.claude/CLAUDE.md`** without the user's explicit request: those corrections travel as
  `MEMORY-FIX` lines to the End report. The number one case is a measurement that invalidated an
  earlier claim: if the task corrected itself out loud, the FILE still holds the false version and
  the next session will read it as fact.
- **Nothing the next session needs may live outside the repo.** A script, a characterisation
  harness, a query you wrote in a temp/scratchpad directory is gone when the session ends. Commit it
  (a repo already has a home for one-off scripts) or state in the End report that it was dropped and
  why. Never leave it implicit.
- Continue to the next pending task. When none remain (or the single TASK-ID is done), produce the
  End report.

## When to pause (AskUserQuestion)

Only the orchestrator talks to the user. A subagent's gate arrives as a `STATUS: blocked` report
naming the decision on `BLOCKED-ON:`; the executor's own list of what counts as a gate is in
`EXECUTOR.md`.

Pause the queue for:

- A `STATUS: blocked` report. A TECHNICAL block on a standard-tier builder forks first (`FORK.md`);
  otherwise, or when the fork finds no winner, mark the task `[~]` and either ask now or
  skip-and-report per the run.
- A **`- [!]` blocker** on the report just returned (Step 9b). Finish the task, log it, flip its
  checkbox, then stop the queue and put the blocker in front of the user, in the conversation, in
  full: what is wrong right now, and the exact thing they have to do. This one is a notification,
  not a question: nothing has to be decided to let the run continue, it has to have been *seen*.
  `AskUserQuestion` with "continue the queue / stop here" is the right shape. A run that pauses at
  task 3 of 20 and says why beats one that finishes 20 and buries the reason in a file nobody opens.
- A `push-pending-consent` report, or a push target that needs human judgment (Step 0's branch and
  push rule).
- Genuine ambiguity about the **target** (the tasks file or repo does not match where you were
  invoked). Confirm the project once before grinding, then run autonomously.

Do NOT pause for: "is this commit message ok", "should I push", "should I run the client doc",
"should I do the next task". Those are part of the autonomous cycle.

## Anti-patterns (orchestrator)

The executor's own list is in `EXECUTOR.md`. These are the ones only this session can commit:

- Invoking loopit on your own initiative. It runs when the user types `/loopit`, never because a
  task queue happens to exist, and never mid-conversation because the work "looks loopable".
- Running the cycle inline "because the task is small". The whole point of the subagent is that
  the task's file reads and review output die with it instead of being re-paid on every later
  message of the run.
- Implementing several tasks then one big review at the end, which defeats the per-task gate.
- Pointing a task subagent at this file instead of `EXECUTOR.md`.
- Dispatching without naming a `model` (see the Execution model).
- Giving the builder a check's path, command or code, or telling it where the checks live. It
  gets the intents and nothing else.
- Reading a check log in full. The gate reads `run-checks.sh` stdout and, on a failure, the
  grepped first error lines.
- Committing a builder's work before the gate said `green-ok` (or the task had no checks).
- Putting a client repo, or one you could not classify, on the fast tier.

## After the run: separate build/deploy (if the repo needs one)

If any shipped task's repo documents a separate build/deploy to reach users (Step 0), e.g. a
mobile build, a manual deploy, run it **once** at the end (not per task), using the repo's
documented command. Capture the result/URL in the End report. Requires a clean git tree and an
authenticated CLI for that tool; if not authenticated, tell the user the one command to run.
If no repo needs one, skip this step.

## End report

In **ad-hoc plan mode** there is no run log and no tasks file: assemble the report from the
subagent's report directly and skip the paragraph below.

When the queue is exhausted (or the single task is done), assemble ONE message from the run
log (`{tasks-file-stem}-run.md`), not from whatever is still in this conversation: a long run gets
summarized mid-flight and the details are the first thing to go. Cover the task ids present in the
CURRENT tasks file; where the log holds entries from earlier sessions (their date stamp gives them
away), say which ones predate this run instead of restating them as fresh work. The message covers:
- Tasks shipped, each with its commit SHA and repo.
- Tasks left `[~]` blocked and the decision each needs.
- The client-doc files written (one per-product folder).
- Each task's `CHECKS:` line (how many checks, first-pass or not, gate rounds), every task that
  shipped with NO executable check and why, and every manual check `/battle-test` could not run.
- Any deferred findings/follow-ups, and any separate build/deploy still required.
- **Memory to correct**: every `MEMORY-FIX` line from this run's log entries (in ad-hoc plan mode,
  from the builder's report), as a numbered list (file, old text, new text), ending with "say ok
  and I apply them". On the user's ok, apply each as an exact replacement; an old text no longer
  found is skipped and named, never approximated. No lines: say "no memory correction needed".
- **Every manual step from this run's `MANUAL-STEPS:` lines, written out in full, `- [!]` first.**
  Re-read this run's log entries (in ad-hoc plan mode, the builder's report) and quote them;
  this is the part of the End report the user acts on directly, and there is no other copy of it
  they will open. Say plainly when there are no blockers. If no task needed anything, say so:
  "nothing needs you" is a useful result.
