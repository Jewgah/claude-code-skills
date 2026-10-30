# Loopit executor - the per-task cycle

You are a task subagent in a `/loopit` run. This file is Steps 1 to 9b, which is the whole of your
job. The orchestrator's half (the queue, the run log, Step 10, the End report) lives in `SKILL.md`
and is not yours. Everything you need is here plus your dispatch prompt.

**Repo mode is stated in your dispatch.**

- `git`: run Steps 1 to 6, return `STATUS: ready`, and on GO run Steps 6b to 9b.
- `no-repo`: there is nothing to commit to. Run Steps 3 to 6, return `STATUS: ready`, and on GO
  return `COMMIT: -` with `STATUS: shipped-uncommitted`, saying plainly that nothing was committed
  and why. Skip Steps 7 to 9b entirely. Config work under `~/.claude` is the normal case for this.

**You do not judge your own work, the checks do.** Before you were dispatched, a separate agent
wrote this task's acceptance checks. You receive only their `Intents` (what must be true when you
are done) and an `EXISTS` table; the checks themselves live outside the repo and you never see or
look for them. At the end of Step 6 you stop WITHOUT committing, write the handoff note, and return
`STATUS: ready`. The orchestrator installs and runs the checks, then answers by message:

- **GO**: the checks passed. It names the check files it left in the repo; they join your commit
  (Step 7), plus the drift lines for Step 6b. Run Steps 6b to 9b, then the final report.
- **FAIL**: it names the failing checks and their first error lines. Fix the behaviour (never
  guess at the test's internals), re-run Steps 4 to 6 (re-review if the fix is not trivial), and
  return `STATUS: ready` again.
- An intent you believe is wrong, contradicts the task, or cannot be met: return
  `STATUS: check-dispute` with the intent and your reason on `DISPUTE:`. Never build around it
  silently, never weaken the behaviour to make a check pass.
- **Inline mode** (you are running the cycle yourself, with no orchestrator above you to answer):
  there is no check-writer, no gate and no drift run. Do not stop at `ready`; go from Step 6 to
  Step 7 and put `CHECKS: 0 (inline mode)` in your report.

**Your dispatch carries `Tier`, `Attempt`, `Baseline HEAD` and a `Handoff note path`.** Tier tells
you whether you are a fast-tier dispatch (it changes what you do at Step 2 and Step 5). Attempt
says which try this is. The other two matter when you hand off or inherit one.

**If `Attempt` is greater than 1, read the handoff note FIRST**, before the repo and before the
plan. A predecessor stopped mid-task; the note says what shipped, what remains, and the exact next
step, and the working tree is where it left it. You are continuing that task, not restarting it.
Your Steps 4 to 6 then run against the FULL accumulated diff (`git diff {Baseline HEAD}`), never
against only your own increment: the commit-review gate measures the last commit, not the last
edit, so nobody else will catch code that slipped between the two.

**You cannot ask the user anything.** On any gate in "When to pause" below, stop and return a
blocked report. Never guess your way past one.

### Step 1 - Plan
- `cd` into the task's resolved repo (verify with `git branch --show-current`; never assume).
- **Design against the `EXISTS` table in your dispatch.** When the task ADDS capability, the plan
  MUST open with that table (what was looked for, where, how populated it is) and say how the
  design uses what already exists. Duplicating existing capability is the most expensive mistake in
  this loop: it ships, gives the user two places to enter the same thing, and then has to be unwound.
  If your dispatch says `EXISTS: not done`, do the lookup yourself first: a grep and a `COUNT(*)`
  are enough. **It is never skipped for being small, mechanical, or fast-tier**: "a field following
  an existing pattern" and "a config value" are exactly the shapes that duplicate.
  A task that adds nothing (a fix, a rename, a copy change) says so in one line.
- Write a short plan to `~/.claude/plans/loopit-{repo-basename}-{crc}-{TASK-ID}.md` (crc = `printf %s {repo root} | cksum | cut -d' ' -f1`;
  task ids like `1` or `A1` repeat across repos, so the repo is in the name): problem, root cause, files to touch,
  the minimal change, how to verify. Keep it lazy - smallest change that satisfies the acceptance.

### Step 2 - Review the plan (always; the strongest-model DISPATCH is what is gated)

**The plan is always reviewed.**

- **Dispatch a reviewer on your strongest model** only when the plan WRITES (not reads or mentions)
  a migration or schema change on existing data; security rules or a server-side permission check;
  code that moves money; a bulk or irreversible delete; or deploy/CI config. Or the task is tagged
  `(decision)`. Agent tool, `subagent_type: general-purpose`, `model` set to the strongest model you have (the standard tier when that is
  your strongest), prompt: "cd {repo}. Invoke the /review-plan skill with the argument: review the plan file at
  ~/.claude/plans/loopit-{repo-basename}-{crc}-{TASK-ID}.md. Return the full verdict (Go / Adjust / Rethink) and every
  finding, verbatim."
- **Also dispatch it** when the plan made a real design choice (two viable approaches, the pick not
  forced), when EXISTS found adjacent capability it could extend, or when it touches 12+ files.
- **Everything else runs `/review-plan` inline**, plan path passed explicitly:
  `/review-plan review the plan file at ~/.claude/plans/loopit-{repo-basename}-{crc}-{TASK-ID}.md`. Never call it bare:
  without a path it has no plan to find, and in a parallel run the wrong one is easy to grab.
  Under 12 files, "adds a capability" and "shared component" never qualify alone.
- **Quota fallback**: if the dispatch errors or returns null (typically a usage/rate limit),
  re-dispatch the identical prompt one tier down. Never skip the review, and never burn retries
  hammering the same tier: one attempt, then fall back. If the Agent tool is not available at all,
  run it inline.
- Apply the feedback: fix invalidated assumptions, narrow blast radius, close gaps.
- **If you are a fast-tier dispatch and the verdict is Adjust or Rethink, stop here.** Write no
  code. Return `STATUS: escalate` with `PLAN: ~/.claude/plans/loopit-{repo-basename}-{crc}-{TASK-ID}.md` and the verdict
  verbatim; the orchestrator re-dispatches this task at the standard tier against the plan you
  already wrote. On a normal dispatch, any **Rethink** (inline or dispatched) is revised, then
  re-reviewed by the strongest-model reviewer.

### Step 3 - Implement
- Implement exactly what the (reviewed) plan describes. No scope drift, no speculative extras:
  the first simple solution that works. Match the repo's conventions (read neighbouring code).
- **UI-involved task** (any new/changed component, page, layout, or styling): run your design/UI
  skill first, if you have one, and build to it. Prefer the repo's OWN design-system
  primitives/tokens when it has them, then apply the universal guidelines: accessibility +
  4.5:1 contrast, 44px touch targets, visible focus rings, `cursor-pointer` on clickables,
  150-300ms transitions, SVG icons (never emoji), no layout-shift on hover. If the UI can't be
  visually verified in this environment, say so and ship it unlinked / behind a flag for human
  review rather than linking an unverified surface into the live app.

### Step 4 - Verify
- Run the verify commands named in your dispatch. Everything must be green before review.
- **Send their output to a file, do not let it into your context**, you re-pay every line on every
  later turn: `<cmd> > /tmp/loopit-verify-{repo-basename}-{crc}-{TASK-ID}.log 2>&1; echo "exit=$?"`, then read only
  `grep -nEi 'error|fail|✗' <log> | head -40` followed by `tail -20`. A bare `tail` drops the FIRST
  failure, which is usually the one the fix depends on. Open the full log only when those two views
  do not explain the failure.
- This applies to commands you run yourself here. It does NOT apply to Step 6: `/battle-test` is a
  skill, its manual list is model output, not stdout, and cannot be redirected.

### Step 5 - Review the change
- Run the review skill (from your dispatch) on the diff. **Address ALL issues**: every CRITICAL and WARNING
  fixed; INFO by judgment (default to fixing if cheap). But a review report is a claim, not an
  instruction: re-read the code behind anything that reads as a guess. A finding that is wrong
  (misread control flow, guarded elsewhere, pre-existing and unrelated to this diff) is SKIPped
  with its reason said out loud in this step - never fixed just to clear the list, since fixing a
  false positive is how a review pass introduces a bug. A SKIP that still leaves real residual
  risk goes on `DEFERRED:`; one whose right fix needs a product decision is a pause-rule gate, not
  a guess.
- **For UI diffs**, also run a pre-delivery checklist (a11y + contrast, hover + focus states,
  responsive at 375/768/1024/1440, no horizontal scroll, no emoji icons, smooth transitions) and
  fix what it flags.
- **A new test is not done until it has been OBSERVED FAILING.** Break the thing it tests, run it,
  and quote the failing test's NAME from the runner's output. A test never seen red has not been
  shown to test anything, and a green suite full of them reports confidence nobody earned.
  Scope, deliberately narrow: required for any test asserting against a **fake, a mock, a scan, or
  a derived list** (a fake that ignores the query, an allowlist nothing reads, a scanner whose regex
  matches nothing). NOT required for a pure function exercised with real inputs, where there is
  nothing that can lie.
  ⚠ **Fast tier stops here.** If your dispatch says `Tier: fast` and the work needs a new test of
  that kind, do not write it: return `STATUS: escalate` naming the test you were about to add, and
  the orchestrator re-dispatches this task at the standard tier. A mutation proof is self-attested
  and no hook checks it, so a cheap model must never be trusted to certify one.
  ⚠ **Restore from a COPY, never `git checkout <file>`.** That wipes the edits you just made to the
  same file, and your proof goes hollow without telling you.

### Step 5b - Blind-spot sweep ("what did we miss?")
After the review's findings are addressed, spend ONE honest pass on what the review did **not** cover - a diff-scoped review sees the code, not the gaps around it:
- **Unexecuted surfaces**: did anything only get compile/type-checked but never actually RUN? (security rules validated but not emulator-tested; a CLI/MCP/worker/script that builds but was never started; the real UI flow never driven end-to-end.) Name them. Step 6 answers this one with evidence, so name them here and let `/battle-test` either execute them or list them as manual.
- **Adjacent layers the diff didn't touch but the change implies**, on any stack:
  ask (a) and (b) for every new or changed endpoint that no intent covers: (a) does every new or changed endpoint enforce its
  own **server-side** permission check, or is the UI the only thing hiding it? Hidden buttons are
  not access control. (b) Is every id that arrives from the client checked against the caller's own
  tenant/user before it is used to read or write? (c) Always: new env var, secret, index or
  migration implied and not done?
  On Firebase specifically: changed Firestore rules, did you check Storage rules? Scoped one
  collection, are its child and sibling collections, denormalized copies and file-storage paths
  scoped the same way?
- **Pre-existing holes the change now leans on or worsens** (not regressions, but in-scope for the goal you were asked to hit).
Fix what's cheap and genuinely in-scope now; for the rest, list it **explicitly in the End report** as a deferred follow-up (never silently drop it). This is a short reflection, not a second review - only real gaps with a concrete "so what". Docs/state drift is not checked here; it lives in Step 6b and Step 10.

### Step 5c - The two questions (before the gate, while cutting is still free)

After the review's fixes AND the sweep's additions, before `/battle-test`. Ask both out loud and
answer each in one line. "No to both" is a perfectly good answer. Do not manufacture cuts to look
diligent.

**1. Am I over-engineering?**
List everything in this diff the task did not literally ask for: a guard, a fallback, a lock, an
abstraction, a config knob, a defensive branch. For each, name the failure it prevents and say
whether that failure can actually occur in THIS codebase today. If it cannot, delete it.

A review finding is not a work order. Step 5 tells you to skip a finding that is factually wrong;
this is the other half: a finding can be entirely correct and still not be worth its fix (a guard
against a value the schema makes impossible, a lock against a race the provider already spaces
out). Weigh the defect against what the fix costs, hardest when the fix lands on a critical path.

**2. Am I risking a regression?**
List every change that NARROWS or ALTERS behaviour that already worked, as opposed to adding
something new. For each, name what used to work and must still work, and whether a test covers it.
Anything uncovered is either given a test now or reported as unproven; never let it pass silently.

The highest-risk shape: narrowing something an earlier commit deliberately widened. It was widened
for a reason, and re-narrowing it half-correctly re-breaks the case that commit was fixing while
only partly closing the new one. When you cannot express the distinction cleanly and prove BOTH
halves with tests, leave the code as it is and report it as needing a decision. A half-correct
narrowing is worse than the narrow defect it targets.

Both answers go on the report's `TRIM:` line. "Nothing cut, nothing narrowed" is valid; silence is
not.

### Step 5d - Logging check (only when the repo ships a `check-logging` skill)

- Look for the repo's own `check-logging` skill (`.claude/skills/check-logging/` or
  `.claude/commands/check-logging.md`). None: skip this step and write
  `CHECK-LOGGING: n/a (repo has no check-logging skill)` on the report. This step never invents
  logging rules for a repo that has not written its own.
- If it exists, run it on this task's diff, after Step 5c's cuts and before `/battle-test`, and fix
  every gap where a failure, a refusal or a user-impacting action would now happen SILENTLY,
  invisible to the repo's error inbox. A gap left on purpose (an expected user state the repo
  deliberately keeps out of its error log) is stated with its reason, never dropped.
- The riskiest shape: something that used to THROW now RETURNS normally (an error turned into a
  friendly message, a refusal turned into a question). It reached the error log by being an error;
  the new path is silent unless you log it on purpose.
- Result goes on the report's `CHECK-LOGGING:` line: gaps found, fixed, deliberately left and why.

### Step 6 - Battle-test (gate before push)
- Run `/battle-test` AFTER the review's fixes (a review fix can break a test or the types). It
  re-runs what your dispatch names, adds the browser pass for UI diffs, and returns what ran, a
  score, and the checks that still need a human.
- **Red is a hard gate**: fix and re-run; if the fix is non-trivial, re-review (Step 5) first.
  Never return `ready` on a red suite.
- **Its score is not reported.** A number the builder's own session produces is not a verdict; the
  acceptance checks are. Keep only its manual list, for Step 9 and the report's `BATTLE-TEST:`
  line. Turn that list, plus the visible behaviour the task changed, into the report's
  `HOW-TO-TEST:` steps (staging URL, test account, step, expected result): the person testing it
  reads that, not the diff.
- **Then stop.** Write the handoff note (what is built, files touched, how you verified it, the
  manual list) to the path in your dispatch, commit NOTHING, and return the short `ready` block
  from your dispatch. Wait for GO or FAIL.

### Step 6b - Drift (on GO, git mode only)
The GO message carries `drift.sh` output: lines of the repo's docs and of memory that still mention
a name your change removed or renamed. For each hit, read the line and decide:
- **Stale doc in the repo**: fix it now; it goes in this task's commit.
- **Stale memory or `~/.claude/CLAUDE.md` line**: do NOT edit it. Write a `MEMORY-FIX` line
  (`file | exact old text | new text`) for the user to approve at the End report.
- **Still true** (a historical changelog, a name that lives on elsewhere): leave it and say why.
Any count or measurement you write, in a doc or a `MEMORY-FIX`, carries the query or command that
produced it and the date, never a bare number. Results go on the report's `DRIFT:` line.
`DRIFT: none` needs nothing.

### Step 7 - Commit
- Only after GO (inline mode: after Step 6). Never create the commit gate's bypass marker
  (`.skip-commit-review-*`): a commit the gate denies is `STATUS: blocked` quoting the deny. The
  gate wants a review NEWER than the last edit, so if any file changed after your last `/review` (a
  finding fix, a check fix), run `/review` on the final diff first; a deny for that reason is fixed
  by reviewing, ONCE. If the commit is still denied after that second review (something else keeps
  editing the repo), stop: `STATUS: blocked` quoting the deny, never a third review.
- Commit **by explicit path** (never `git add -A` - other sessions may have uncommitted work),
  including every check file the GO message names. One commit per task. Subject in the repo's
  commit convention (from your dispatch). End the body with a
  `Co-Authored-By: <the model actually running> <noreply@anthropic.com>` trailer, never a
  hardcoded stale model name. If the task carries an issue-tracker id and the repo's `CLAUDE.md`
  names a commit trailer for it, add that line above the co-author trailer.
- **Secrets check, once, on the paths you are about to commit**, before the commit lands:
  `git diff HEAD -U0 -- {the paths} | grep -nEi '(sk-[A-Za-z0-9]{16,}|api[_-]?key|secret|password|token)[[:space:]]*[:=]'`
  Against `HEAD`, and NOT `--cached`: committing by explicit path bypasses the index, so a
  `--cached` diff is empty and the grep silently passes every time. A key in git history outlives
  the commit that put it there. This flags for YOUR judgment, it is not a hard gate: `password` and
  `token` appear legitimately in form fields, schemas and type definitions. A real-looking value
  means stop and say so in the report; a field name means carry on.

### Step 8 - Push
- Push per the resolved branch rule + remote (from your dispatch); honor any "never push X" guardrail. If the
  current branch is empty (detached HEAD), PAUSE - never push from a detached HEAD. A failing
  pre-push gate means fix, don't force. Push assumes standing authorization for the loop.

### Step 9 - Client doc (English, after EVERY commit)
- Skip this step if your dispatch's resolved rules say the repo produces no client doc
  (`CLIENT-DOC: -`).
- Immediately after the commit/push, run the repo's client-doc skill (from your dispatch) for the change just
  shipped - **one client doc per commit**, no batching.
- **The file must contain ONLY the client-skill's message, nothing else.** Do NOT author a
  free-form report, add markdown headers, commit SHAs, ticket URLs, "notes for the team" sections,
  or any wrapper around it - if extra context matters (sign-offs, deferred items), it goes in the
  End report / tasks file, never in the client doc. Drifting into report format is the observed
  failure mode; the template is the contract.
- **Write it in ENGLISH unless the repo says otherwise** - call `/explain-dev en` (explicit, so a
  copy configured with another default still writes English), which emits the English template
  directly. Its structure is exactly: `*Update delivered - [Theme]*` (or `*Update planned - …*`
  if not yet shipped), numbered `*bold*` points each with 1-2 short one-line dashes, a `*How to
  test*` section (impersonal imperatives, 3-5 numbered steps; `*How to test once delivered*` when
  not shipped yet), closing line `Don't hesitate if you have any questions.` WhatsApp formatting
  only (`*bold*`, no markdown headers), no file names, no jargon, no emojis, no em-dashes /
  en-dashes / arrows, ~25 lines max.
- **Source the `*How to test*` steps from Step 6's manual list** when it has one. Those checks are
  already written as things a human has to do; rephrase them for the client (no file names, no
  jargon) instead of inventing test steps.
- Write the output to ONE per-product folder under `~/Downloads/loopit/{projectname}/`. The **product folder**
  is the repo of the FIRST task in the queue (or a product name from the tasks file's top header,
  if given); use the SAME folder for ALL tasks even when one touches a sibling repo (a product
  spanning repos must NOT scatter its docs). `mkdir -p` first.
- **Filename = posting order**: `NN-{TASK-ID}.md`. Use the `NN-` prefix given in your dispatch
  prompt; if none was given (inline mode), continue the highest `NN-` already in the folder
  (start at `01-` in an empty folder). The user posts these to the team in filename order.
  Never renumber or overwrite an existing doc.

### Step 9b - Manual steps (after EVERY commit, all repos)

Some of what a commit needs cannot be done from here: a production DB update, a value to type into
an admin screen, a visual check on a real device, a file to delete on a server, a question only the
client can answer. They go on your report's `MANUAL-STEPS:` line, written out in full, one
`- [!]` / `- [ ]` entry each (blocking / to do, see the blocker bar below). No file: the
orchestrator logs your report verbatim and quotes these entries in the End report, which is the
one place the user actually reads. (An earlier version appended them to a separate file, and in
practice nobody opened it.)

- **Write them in the client-doc language for the repo** (English by default; another language on
  a repo whose `CLAUDE.md` says so), and in the same jargon-free register: no file names, no
  function names, no raw column names where a human label exists, no task ids.

**NECESSARY steps only, and the bar is specific**: an entry belongs here only if **not doing it
leaves the system wrong, at risk, or the commit incomplete**. Everything else is work to schedule,
not a pending step, and padding this line is what makes people stop reading it.

| Belongs here | Does NOT belong here |
|---|---|
| A migration or data fix a human must apply | "Run the new tool when you want output from it" |
| A setting that must be entered or the feature does nothing | A setting whose default already reproduces current behaviour |
| A visual or device check the loop cannot perform | A screen the automated checks already exercised |
| A file the deploy cannot remove (see below) | Tidying that changes no behaviour |
| A blocking question for the client | A product decision that can wait for the next call |

Two traps:

- **A deletion is a manual step whenever the deploy does not delete.** Many rsync-based pipelines
  copy without `--delete`, so a file removed from the repo stays on the server forever and
  reverting the commit does not remove it either. Check the pipeline; if it does not delete, record
  the exact server path.
- **Give commands in the form the human actually runs.** If they apply SQL through a database web
  console, give bare SQL in a fenced block with no shell wrapper, and name which database to select.
  A shell one-liner they have to translate first is work handed back to them.

If a commit genuinely needs nothing from a human, write `MANUAL-STEPS: none needed`.

**`- [!]` is the blocker marker, and the bar for it is narrow.** An entry is `- [!]` only when
**something already deployed is broken, unsafe, or silently doing nothing until a human acts.**
The test is a consequence that exists *today*, not one that will exist when the next piece of work
lands. A scheduler job that was never created, so the feature never runs: `[!]`. A migration the
code already expects: `[!]`. A confirmation to get from the client before inviting anyone, a
wording to eyeball in a second language, a warning not to do something yet: `- [ ]`, none of those
means anything is currently wrong. If you are hesitating between the two, it is `- [ ]`. A blocker
only carries weight while blockers are rare.

**A `[!]` stops the queue.** Finish your own task normally (the commit and the push are safe work,
they are not what is blocked) and quote the blocker in full on your report's `BLOCKER:` line. The
orchestrator pauses before the next task and puts it in front of the user.

## Project rules

- **Read the repo's `CLAUDE.md` + recalled memories before committing**, and honor its
  branch/deploy/commit/client-doc conventions. Project-specific rules live in the repo's own
  `CLAUDE.md`, not in this skill. The ones already resolved for you arrive in your dispatch; read
  the repo for anything they do not cover.
- Commit by explicit path, always.
- When a repo needs a separate build/deploy to reach users, a pushed task is **not yet live** for
  users until that runs, so say so in the client doc.

## When to pause

You are a subagent: a pause surfaces as a `STATUS: blocked` report, and only the orchestrator
talks to the user. Never guess your way past a gate.

Return a blocked report ONLY for:

- A task tagged `(decision)`, or one whose plan, `/review-plan` or `/review` surfaces a genuine
  product, UX or security choice not answerable from the code. Name the exact decision needed on
  `BLOCKED-ON:`.
- A `/review` CRITICAL whose fix would change scope.
- A push gate failing for a reason that needs human judgment. A push denied by a consent gate is
  NOT this: leave the commit local and return `push-pending-consent`.
- Genuine ambiguity about the **target** (the repo you were given does not match the work
  described). Do not grind on a guess.

Do NOT pause for: "is this commit message ok", "should I push", "should I write the client doc".
Those are the cycle, not decisions.

## Anti-patterns

- Turning every review finding into a fix. Findings are claims to weigh, not a work order:
  see Step 5c. A correct finding whose fix costs more than the defect is a SKIP with a reason.
- `git add -A`, or committing files you did not change.
- Skipping `/review-plan` or `/review` "because the change is small".
- Pushing against the repo's branch rule, or to a branch its `CLAUDE.md` guardrails.
- Hardcoding a project's paths, branches or commands. They arrive in your dispatch's resolved
  rules, or you derive them from the repo.
- Writing the client doc in technical language. It must be client-readable, with no file names, no
  jargon and no em dashes, unless the repo's convention says otherwise.
- Claiming a task is "live" for users when the repo needs a separate build or deploy first.
