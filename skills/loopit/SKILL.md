---
name: loopit
description: Drive a task queue (loop-tasks.md) to completion in ANY repo. Detect the repo's own rules, then for each task plan -> /review-plan -> implement -> verify -> /review -> fix all findings -> /battle-test -> commit -> push -> client doc -> mark done. Each task runs in its OWN subagent (context isolation, token-cheap); the main session only orchestrates. Autonomous between tasks; pauses only for genuine product decisions.
disable-model-invocation: true
argument-hint: "[tasks-file path (default ./loop-tasks.md), or a single TASK-ID to run just that one]"
---

# Loopit - run a task queue through the full delivery flow

You are an **autonomous delivery runner**, project-agnostic. Input: `$ARGUMENTS` - a path to a
tasks file (default `./loop-tasks.md`), or a single `TASK-ID` to run only that task.

Process tasks **strictly one at a time, top to bottom**, each through the complete cycle below.
The loop is autonomous *between* tasks - do not ask "should I continue" after each one. Pause only
at the explicit gates in "When to pause".

**Nothing here is hardcoded to a specific project.** Every project-specific rule (branch, deploy,
commit style, client-doc format, post-push build) is **derived from the target repo** in Step 0 -
primarily from its `CLAUDE.md` + recalled memories + its tooling files. If a repo needs a special
rule, it belongs in that repo's `CLAUDE.md`, not in this skill.

## Inputs

- `$ARGUMENTS` empty → read `./loop-tasks.md` in the current directory.
- `$ARGUMENTS` = a path → use that tasks file.
- `$ARGUMENTS` = a `TASK-ID` (e.g. `FX-A03`) → run only that task, then stop.

The tasks file's directory anchors any relative `repo` paths (below).

## Tasks file format

A markdown checklist. Each line:

```
- [ ] TASK-ID | repo | Title - short description / acceptance / notes
```

- `[ ]` = pending, `[x]` = done, `[~]` = blocked (needs a decision; skip and report).
- `repo` = the working directory for the task. Resolve as: an **absolute path** as-is; a
  **relative path** against the tasks-file's directory; `.` or empty → the current repo. Do NOT
  assume any fixed parent directory.
- Lines starting with `#` are section headers; ignore for processing.
- A task line may be followed by indented grounding notes, one per line, starting with two
  spaces and `> ` (attachment digests, decisions from a ticket's comments, and similar). They
  belong to the task above and are passed VERBATIM to that task's subagent as Extra
  grounding; they are not tasks.
- A task tagged `(decision)` in its notes needs product input - see "When to pause".

## Step 0 - Detect the project's rules (do this first, per repo involved)

Before running tasks, `cd` into the repo and establish its rules **from the repo itself** - never
assume. Read its `CLAUDE.md` + recalled memories, inspect git, and detect tooling:

- **Repo + git**: `git rev-parse --show-toplevel`, `git branch --show-current` (empty → detached
  HEAD; see Step 8), the default branch (`git symbolic-ref --quiet --short
  refs/remotes/origin/HEAD`), and the push remote (`origin` if present, else the repo's single
  remote - if several and none is `origin`, ask). **Re-run this detection for each distinct repo
  in the queue** - rules are per-repo.
- **Branch & push rule** (safety-critical - get this right before any push):
  1. If `CLAUDE.md`/memory states a rule ("push `dev`, a gate promotes `main`"; "never push
     `main`"), use it.
  2. Else look for an IMPLICIT rule: scan `.github/workflows/*.y*ml` + any pre-push hook for a
     protected/promote/green-gate pattern (e.g. a workflow on push to `dev`/`develop`/`staging`
     that fast-forwards `main`) and infer the push branch from it.
  3. Else default to **push the current branch** - UNLESS the current branch IS the
     default/production branch (`main`/`master`) AND a non-production sibling
     (`dev`/`develop`/`staging`) exists: then do NOT auto-push to production - PAUSE and confirm
     the target. (This is the guardrail for repos whose "never push prod directly" rule lives only
     in CI config, not `CLAUDE.md`.)
  Never switch or guess a branch; honor any "never push X" guardrail (documented or inferred).
- **Verify commands**: detect what the repo actually has - `package.json` scripts
  (`typecheck`/`lint`/`test`/`build`), `composer.json` scripts (`cs`/`test`), a `Makefile`,
  `cargo`/`go`/`pytest`, etc. Run the ones that exist. If a change is a single language file and no
  suite covers it, fall back to the language's own check (e.g. `php -l`, `tsc --noEmit`) plus a
  minimal runnable assertion. These commands are the cheap Step 4 gate; the deeper pre-push gate
  (Step 6) delegates detection to `/battle-test`, so do not duplicate that work here.
- **Review skill**: `/review` by default; use `/review-deep` if `CLAUDE.md`/memory calls for a
  deeper per-commit review.
- **Commit convention**: match the repo's existing `git log` style (Conventional Commits, a
  `prefix:` style, etc.). Default to Conventional Commits if the log is mixed/empty.
- **Client-doc convention**: how this repo produces the human-facing change note - `/explain-dev`
  (call it as `/explain-dev en` for English; no argument gives French), or none. **Language is
  ENGLISH by default**, and stays English unless the repo's `CLAUDE.md`
  explicitly says otherwise. Output goes to ONE per-product folder under `~/Downloads/{projectname}/`.
- **Post-push build/deploy**: does reaching users need a separate step after push (a mobile build,
  a manual deploy)? Check `CLAUDE.md` (a "Build"/"Deploy"/"Release" section) and tell-tale config
  (`app.json`/`eas.json` → EAS; a deploy script). If the command is documented, note it for the
  after-run step; if a build is clearly needed but the command isn't documented, ASK before
  running it (don't guess platform/profile).

**State the resolved rules in one line before the first task** (branch/push, verify cmds, review
skill, client-doc target) so the run is transparent.

## Execution model: one subagent per task (context isolation)

Why: in a single session, task #8 pays to re-read everything tasks #1-7 put in context
(file reads, review output, battle-test logs) on every message. Cache reads are ~90% of a
loop's token bill. A per-task subagent starts clean, runs the whole cycle, and only its
short report enters this session.

Roles:

- **Orchestrator** (this session): Step 0 once per repo, owns the tasks file, then per task:
  dispatch one subagent, read its report, run Step 10, dispatch the next. Strictly
  sequential, never parallel (tasks may touch the same files and commits must stay ordered).
- **Task subagent** (Agent tool, `subagent_type: general-purpose`, one per task): executes
  Steps 1-9b for its ONE task, then returns the report below. Dispatch on the session's
  model, EXCEPT when the session runs on a premium-priced model: step the subagent down to
  your standard tier. Routine delivery does not need the expensive model; save it for the
  Step 2 plan review, where the leverage is. Exception: if you are ALREADY a subagent,
  execute the cycle inline instead of nesting.

Dispatch prompt template (fill the {braces}; keep it self-contained, the subagent sees
nothing of this session):

    You are executing ONE task from a /loopit queue. Read
    ~/.claude/skills/loopit/SKILL.md and execute "The cycle" Steps 1-9b ONLY, for the
    single task below. Do not touch the tasks file (orchestrator's job).

    Resolved repo rules (Step 0 already done, do not redo):
    {resolved rules: repo path, branch/push rule, verify cmds, review skill,
     commit convention, client-doc skill + language}

    Task line (verbatim):
    {task line}
    Extra grounding: {the task's indented > notes from the tasks file, verbatim, or "none"}

    Client doc goes to ~/Downloads/{productname}/ with filename prefix {NN}-.
    Manual steps (Step 9b) go APPENDED to ~/Downloads/{productname}/manualstepstodo.md,
    same folder. Create that file with its header if it does not exist yet, then
    append only, never rewrite, never delete an existing section. NECESSARY steps
    only: an entry belongs there only if NOT doing it leaves the system wrong, at
    risk, or the commit incomplete. If this commit needs nothing from a human,
    append nothing and say so in the report.

    You cannot ask the user anything. On a "When to pause" gate (product decision,
    scope-changing CRITICAL, risky push target): STOP and return a blocked report,
    never guess. If your setup gates pushes and the push is denied: leave the
    commit local and report push-pending-consent; the orchestrator handles it.

    Runaway guard: if you are not converging after ~50 tool calls, or the suite is
    red twice for the same cause, stop and return a blocked report with your
    findings so far instead of grinding.

    End with EXACTLY this report block:
    STATUS: shipped | blocked | push-pending-consent
    COMMIT: {sha or -}
    BATTLE-TEST: {score}/100; manual: {list or -}
    CLIENT-DOC: {path or -}
    MANUAL-STEPS: {appended: yes/no, and the section name, or "none needed"}
    DEFERRED: {follow-ups or -}
    RECORD-CORRECTIONS: {claims in tasks file/CLAUDE.md/memory the work invalidated, or -}
    BLOCKED-ON: {exact decision needed, only if blocked}

Orchestrator, after each report: run Step 10 from it (flip checkbox, apply
RECORD-CORRECTIONS). On push-pending-consent: ask the user, then perform whatever your
setup's push gate requires as its OWN step and push again from here. On
blocked: mark `[~]` and ask or skip-and-report per the run. The orchestrator assigns
each dispatch its `NN-` client-doc prefix so subagents never race on numbering.
Spot-check each reported CLIENT-DOC file: its first line must match the `*Update
delivered` / `*Update planned` template; anything else (headers, SHAs, wrapper prose)
gets fixed before the next dispatch - format drift is the observed failure mode.

Note the repo's HEAD (`git rev-parse HEAD`) before each dispatch. Dead or garbled subagent
(no parsable report): establish the truth from the repo, not from the report. A commit
newer than the noted HEAD means the task shipped (reconstruct the report fields from the
commit and the client-doc folder); no new commit means mark it `[~]` with what you found.
Exception, the clean death: no report, no new commit, clean tree means the subagent died
before doing anything (transient API failure). Re-dispatch the identical prompt ONCE;
only a second death marks the task `[~]`.
And after EVERY report, dead or shipped: `git status --porcelain` must be clean before the
next dispatch. Complete leftovers belong in the task's commit, incomplete ones get stashed
and named in the End report.

## Concurrent loops (different repos only)

Several /loopit sessions in parallel are fine when each targets a DIFFERENT repo and tasks
file: the tasks file, the plans, the client-doc folders and the commit-review gate are all
per-repo, so they don't interact. Never point two loops at the same tasks file (the
checkbox flips and HEAD baselines would race); there is deliberately no lock file - one
loop per repo is the rule. If your setup gates pushes behind a consent step, check that
its state is per-repo rather than global before running loops in parallel: a global marker
lets two loops consume each other's consent. Either way, one consent per push - ask each
time.

## The cycle (per task)

Run these in order for ONE task, then move to the next pending task. **These steps execute
INSIDE the per-task subagent** (see Execution model above); Step 10 is the orchestrator's.

### Step 1 - Plan
- `cd` into the task's resolved repo (verify with `git branch --show-current`; never assume).
- **Does it already exist? Look before you design.** When the task ADDS capability (a column, a
  table, a setting, an endpoint, a screen section, a config key), the plan MUST open with a short
  "what already exists" table: what you looked for, where you looked, and **how populated it is**.
  A grep and a `COUNT(*)` are enough; this is a lookup, not an investigation.
  Two real cases from one afternoon: a plan that added three empty inputs next to fields already
  filled on 203 rows out of 203, and a plan that created a settings table when a key/value
  `settings` table already existed with its own controller helpers. Neither was findable by
  reading the code being changed, both were one query away. Duplicating existing capability is the
  most expensive class of mistake in this loop: it ships, it confuses the user with two places to
  enter the same thing, and it then has to be unwound.
  A task that adds nothing (a fix, a rename, a copy change) skips this and says so in one line.
- Write a short plan to `~/.claude/plans/loopit-{TASK-ID}.md`: problem, root cause, files to touch,
  the minimal change, how to verify. Keep it lazy - smallest change that satisfies the acceptance.

Note on where the OTHER measuring discipline lives: "prove your riskiest assumption with a cheap
runnable check rather than by reading code" is already in `/review-plan`, and it works precisely
because that step ends in a stated Go / Adjust / Rethink verdict. Do not copy it here. What Step 1
adds is narrower and different in kind: an existence lookup that must happen BEFORE the design,
because a review can only critique the plan it is given.

### Step 2 - Review the plan (best available model, with a fallback)
- Plan review is the ONE step that gets the biggest model you have: it is the highest-leverage
  call in the cycle (a design flaw caught here is 10x cheaper than one caught at Step 5), and its
  context is tiny (the plan file plus spot checks), so the premium rate costs pennies here.
- Dispatch a reviewer agent: Agent tool, `subagent_type: general-purpose`, with `model` set to
  your strongest tier, prompt: "cd {repo}. Invoke the /review-plan skill with the argument:
  review the plan file at ~/.claude/plans/loopit-{TASK-ID}.md. Return the full verdict
  (Go / Adjust / Rethink) and every finding, verbatim."
- **Quota fallback**: if that dispatch errors or returns null (the Agent tool's terminal-failure
  result, typically a usage/rate limit), re-dispatch the identical prompt one tier down. Never
  skip the review, and never burn retries hammering the same tier: one attempt, then fall back.
- If the Agent tool is not available in your context, run `/review-plan` inline instead.
- Apply the feedback: fix invalidated assumptions, narrow blast radius, close gaps. If the
  verdict is **Rethink**, revise and re-dispatch before any code.

### Step 3 - Implement
- Implement exactly what the (reviewed) plan describes. No scope drift, no speculative extras -
  the first simple solution that works. Match the repo's conventions (read neighbouring code).
- **UI-involved task** (any new/changed component, page, layout, or styling): run your design/UI
  skill first, if you have one, and build to it. Prefer the repo's OWN design-system
  primitives/tokens when it has them, then apply the universal guidelines: accessibility +
  4.5:1 contrast, 44px touch targets, visible focus rings, `cursor-pointer` on clickables,
  150-300ms transitions, SVG icons (never emoji), no layout-shift on hover. If the UI can't be
  visually verified in this environment, say so and ship it unlinked / behind a flag for human
  review rather than linking an unverified surface into the live app.

### Step 4 - Verify
- Run the verify commands detected in Step 0. Everything must be green before review.

### Step 5 - Review the change
- Run the review skill (Step 0) on the diff. **Address ALL issues**: every CRITICAL and WARNING
  fixed; INFO by judgment (default to fixing if cheap).
- **For UI diffs**, also run a pre-delivery checklist (a11y + contrast, hover + focus states,
  responsive at 375/768/1024/1440, no horizontal scroll, no emoji icons, smooth transitions) and
  fix what it flags.

### Step 5b - Blind-spot sweep ("what did we miss?")
After the review's findings are addressed, spend ONE honest pass on what the review did **not** cover - a diff-scoped review sees the code, not the gaps around it:
- **Unexecuted surfaces**: did anything only get compile/type-checked but never actually RUN? (security rules validated but not emulator-tested; a CLI/MCP/worker/script that builds but was never started; the real UI flow never driven end-to-end.) Name them. Step 6 answers this one with evidence, so name them here and let `/battle-test` either execute them or list them as manual.
- **Adjacent layers the diff didn't touch but the change implies**: changed Firestore rules → did you check Storage rules? Scoped one collection → are its child/sibling collections, denormalized copies, and any file-storage paths scoped the same way? New env/secret/index/migration needed and not done?
- **Pre-existing holes the change now leans on or worsens** (not regressions, but in-scope for the goal you were asked to hit).
Fix what's cheap and genuinely in-scope now; for the rest, list it **explicitly in the End report** as a deferred follow-up (never silently drop it). This is a short reflection, not a second review - only real gaps with a concrete "so what".

(Docs/state drift used to be a bullet here and was reliably skipped: this step produces no artefact, so nothing reveals its absence. It now lives in Step 10, which always runs and already edits a file. Do not add it back here: a check with two homes has none.)

### Step 6 - Battle-test (gate before push)
- Run `/battle-test` AFTER the review's fixes (a review fix can break a test or the types). It
  re-runs what Step 0 detected, adds the browser pass for UI diffs, and returns three things: what
  ran, a score out of 100, and the checks that still need a human.
- **Red is a hard gate**: fix and re-run; if the fix is non-trivial, re-review (Step 5) first.
  Never commit or push on a red suite.
- **A low score is not a gate.** Green with a thin score still ships; record the score and the
  reason in the End report rather than blocking the queue on it.
- Keep its manual list for Step 9 and the End report. Anything it could not execute stays visible.

### Step 7 - Commit
- Commit **by explicit path** (never `git add -A` - other sessions may have uncommitted work).
  One commit per task. Subject in the repo's commit convention (Step 0). End the body with a
  `Co-Authored-By: <the model actually running> <noreply@anthropic.com>` trailer (e.g.
  `Claude Opus 5`), never a hardcoded stale model name.

### Step 8 - Push
- Push per the resolved branch rule + remote (Step 0); honor any "never push X" guardrail. If the
  current branch is empty (detached HEAD), PAUSE - never push from a detached HEAD. A failing
  pre-push gate means fix, don't force. Push assumes standing authorization for the loop.

### Step 9 - Client doc (English, after EVERY commit)
- Immediately after the commit/push, run the repo's client-doc skill (Step 0) for the change just
  shipped - **one client doc per commit**, no batching.
- **The file must contain ONLY the client-skill's message, nothing else.** Do NOT author a
  free-form report, add markdown headers, commit SHAs, ticket URLs, "notes for the team" sections,
  or any wrapper around it - if extra context matters (sign-offs, deferred items), it goes in the
  End report / tasks file, never in the client doc. Drifting into report format is the observed
  failure mode; the template is the contract.
- **Always write it in ENGLISH** - call `/explain-dev en`, which emits the English template directly
  (no translation step). Its structure is exactly: `*Update delivered - [Theme]*` (or `*Update planned - …*`
  if not yet shipped), numbered `*bold*` points each with 1-2 short one-line dashes, a `*How to
  test*` section (impersonal, infinitive, 3-5 numbered steps; `*How to test once delivered*` when
  not shipped yet), closing line `Don't hesitate if you have any questions.` WhatsApp formatting
  only (`*bold*`, no markdown headers), no file names, no jargon, no emojis, no em-dashes /
  en-dashes / arrows, ~25 lines max.
- **Source the `*How to test*` steps from Step 6's manual list** when it has one. Those checks are
  already written as things a human has to do; rephrase them for the client (no file names, no
  jargon) instead of inventing test steps.
- Write the output to ONE per-product folder under `~/Downloads/{projectname}/`. The **product folder**
  is the repo of the FIRST task in the queue (or a product name from the tasks file's top header,
  if given); use the SAME folder for ALL tasks even when one touches a sibling repo (a product
  spanning repos must NOT scatter its docs). `mkdir -p` first.
- **Filename = posting order**: `NN-{TASK-ID}.md`. Use the `NN-` prefix given in your dispatch
  prompt; if none was given (inline mode), continue the highest `NN-` already in the folder
  (start at `01-` in an empty folder). The user posts these to the team in filename order.
  Never renumber or overwrite an existing doc.

### Step 9b - Manual steps file (after EVERY commit, all repos)

Some of what a commit needs cannot be done from here: a production DB update, a value to type into
an admin screen, a visual check on a real device, a file to delete on a server, a question only the
client can answer. Those evaporate if they live only in a chat reply. They go in ONE per-product
file that accumulates across the whole project.

- **Path**: `~/Downloads/{projectname}/manualstepstodo.md`, the SAME folder as the Step 9 client
  docs (same product-folder rule: the repo of the FIRST task in the queue, or the product name from
  the tasks file header).
- **Create it if it does not exist**, with a short header stating what the file is, the
  `- [ ]` / `- [x]` convention, and the rule that nothing is ever deleted from it (a handled entry
  gets ticked, it does not disappear). Then never rewrite it again: **APPEND only.**
- **One `##` section per commit**, named after the FEATURE, never after the task id (the
  no-internal-sequencing-label rule applies to this file exactly as it does to client docs).
- **Write it in the client-doc language for the repo** (English by default; French on a repo whose
  `CLAUDE.md` says so), and in the same jargon-free register: no file names, no function names, no
  raw column names where a human label exists.

**NECESSARY steps only, and the bar is specific**: an entry belongs here only if **not doing it
leaves the system wrong, at risk, or the commit incomplete**. Everything else is work to schedule,
not a pending step, and padding this file is what makes people stop reading it.

| Belongs here | Does NOT belong here |
|---|---|
| A migration or data fix a human must apply | "Run the new tool when you want output from it" |
| A setting that must be entered or the feature does nothing | A setting whose default already reproduces current behaviour |
| A visual or device check the loop cannot perform | A screen the automated checks already exercised |
| A file the deploy cannot remove (see below) | Tidying that changes no behaviour |
| A blocking question for the client | A product decision that can wait for the next call |

Two traps worth stating, because both have cost real time on a live client project:

- **A deletion is a manual step whenever the deploy does not delete.** Many rsync-based pipelines
  copy without `--delete`, so a file removed from the repo stays on the server forever and
  reverting the commit does not remove it either. Check the pipeline; if it does not delete, record
  the exact server path.
- **Give commands in the form the human actually runs.** If they apply SQL through a database web
  console, give bare SQL in a fenced block with no shell wrapper, and name which database to select.
  A shell one-liner they have to translate first is work handed back to them.

If a commit genuinely needs nothing from a human, **append nothing**. Say so in the End report
instead. Name the file and the section in the End report whenever you do append.

### Step 10 - Mark done & loop (ORCHESTRATOR, from the subagent's report)
- Flip the task's checkbox to `[x]` (or `[~]` if blocked) in the tasks file.
- **Reconcile the record with what you LEARNED, not only with what you shipped.** In the SAME edit,
  correct anything the tasks file, `CLAUDE.md` or memory now contradicts. The number one case is a
  measurement that invalidated an earlier claim: if you corrected yourself out loud during the task,
  the FILE still holds the false version, and the next session will read it as fact with no way to
  know it is wrong. Shipping the right code while leaving the wrong note is still a defect.
- **Nothing the next session needs may live outside the repo.** A script, a characterisation
  harness, a query you wrote in a temp/scratchpad directory is gone when the session ends. Commit it
  (a repo already has a home for one-off scripts) or state in the End report that it was dropped and
  why. Never leave it implicit.
- Continue to the next pending task. When none remain (or the single TASK-ID is done), produce the
  End report.

Why these two live HERE and not in the blind-spot sweep: this step runs on every single task and
already edits a file, so a skipped reconciliation shows up as a stale line someone can point at. The
sweep produces no artefact, which is precisely why the same check was skipped there.

## Project rules

- **Read each repo's `CLAUDE.md` + recalled memories before committing**, and honor its
  branch/deploy/commit/client-doc conventions (Step 0). Project-specific rules live in the repo's
  own `CLAUDE.md`, not in this skill.
- Commit by explicit path, always (global rule).
- When a repo needs a separate build/deploy to reach users (Step 0), a pushed task is **not yet
  live** for users until that runs - say so in the client doc.

## When to pause (AskUserQuestion)

In subagent mode a pause surfaces as a `STATUS: blocked` report; only the ORCHESTRATOR
talks to the user. Subagents never guess their way past a gate.

Pause ONLY for:
- A task tagged `(decision)`, or one whose plan/`/review-plan`/`/review` surfaces a genuine
  product/UX/security choice not answerable from the code. Mark it `[~]` and either ask now or
  skip-and-report per the run.
- A `/review` CRITICAL whose fix would change scope.
- A push gate failing for a reason that needs human judgment.
- Genuine ambiguity about the **target** (e.g. the tasks file / repo doesn't match where you were
  invoked) - confirm the project once before grinding, then run autonomously.

Do NOT pause for: "is this commit message ok", "should I push", "should I run the client doc",
"should I do the next task". Those are part of the autonomous cycle.

## Anti-patterns

- Running the cycle inline in the orchestrator session "because the task is small". The
  whole point of the subagent is that the task's file reads and review output die with it
  instead of being re-paid on every later message of the run.
- Implementing several tasks then one big review at the end - defeats the per-task gate.
- `git add -A` / committing files you didn't change.
- Skipping `/review-plan` or `/review` "because the change is small".
- Pushing against the repo's branch rule, or to a branch its `CLAUDE.md` guardrails.
- Hardcoding one project's paths/branches/commands into the run - derive them (Step 0).
- Writing the client doc in technical language - it must be client-readable (no file names, no
  jargon, no em-dashes) unless the repo's convention says otherwise.
- Claiming a task is "live" for users when the repo needs a separate build/deploy first.

## After the run - separate build/deploy (if the repo needs one)

If any shipped task's repo documents a separate build/deploy to reach users (Step 0) - e.g. a
mobile build, a manual deploy - run it **once** at the end (not per task), using the repo's
documented command. Capture the result/URL in the End report. Requires a clean git tree and an
authenticated CLI for that tool; if not authenticated, tell the user the one command to run.
If no repo needs one, skip this step.

## End report

When the queue is exhausted (or the single task is done), assemble ONE message from the
collected per-task reports:
- Tasks shipped, each with its commit SHA and repo.
- Tasks left `[~]` blocked and the decision each needs.
- The client-doc files written (one per-product folder).
- Each task's battle-test score, and every manual check `/battle-test` could not run. A task that
  shipped on a thin score is stated as such, not rounded up.
- Any deferred findings/follow-ups, and any separate build/deploy still required.
- **A pointer to `manualstepstodo.md` and a short list of what is still open in it.** This is the
  only part of the End report the user acts on directly, so lead with the entries that block
  something and say plainly when there are none. Do not restate entries already ticked.
  If the run added nothing to that file, say that too: "nothing needs you" is a useful result and
  it is only credible if the file is normally kept honest.
