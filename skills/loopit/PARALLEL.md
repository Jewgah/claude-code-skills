# Loopit: build up to three tasks in parallel

Read by the orchestrator only when SKILL.md sends it here. The slow part of a task is the
builder's Steps 1 to 6; landing (commit, push, Step 10) stays one task at a time, in queue order.
Batching is the default whenever the rules below allow it.

- **Runnable** = `[ ]`, not in a live batch or prefetch, not waiting to re-run alone, and
  batchable: same git repo, checks (`has_runner: yes`), no `(fork)` or `(decision)` tag, no `[!]`
  open, no compose stack found in Step 0 (stacks fight over host ports).
- **Batch = up to 3 runnable tasks, picked from the next 8 `[ ]` lines.** The first `[ ]` task must
  be runnable, else it runs alone first, the normal way, and no batch forms past it. Then add the
  next runnable tasks, in queue order, whose files are disjoint from every member. A batch of 1 is
  just a normal task: main tree, no worktree. A skipped task is first in line for the next batch,
  so a later task may land before it: that is the one exception to SKILL.md's queue order.
- **Never batch a dependent.** A task whose line or `>` notes name the ID or ticket of a task not
  yet `[x]` (skipped, in the same batch, or still landing) waits until that task is `[x]`.
- **Disjoint files, predicted then proved.** Before batching, name the files each task will touch
  (task line, its `>` notes, one grep). Any shared file, or a shared generated one (a lockfile, a
  snapshot, a rules file plus its proof, a doc both would edit): not in the same batch. The
  prediction is a guess, so the proof comes after Step 6 (below).
- **Prefetch.** Once every member is green, none has left, and only landing remains, dispatch the
  next batch now, whole, in ONE message, in fresh worktrees off the current HEAD, with the members
  still landing counted for disjointness. At most 3 builders are in Steps 1 to 6 at once; landing
  builders wait for GO and do not count. A prefetched builder stops at `ready` and its batch lands
  nothing until the current batch is landed and pushed. A `[!]`, a refused push or a stopped queue:
  prefetched builders stay at `ready`, nothing of theirs lands, and the End report lists them with
  their worktrees. Dispatching into a worktree does not need the main tree clean; SKILL.md's
  clean-tree check runs before each patch apply instead.
- **One worktree each**: `git worktree add ~/.claude/loopit-par/{repo-basename}-{crc}/{TASK-ID} HEAD`.
  A worktree has no gitignored files, so before dispatch symlink the dependency folders the verify
  commands need (`node_modules`, `functions/node_modules`, `vendor`...) and copy the `.env*` files
  from the main tree. Never `npm install` into a symlinked folder.
- **Check-writers for the whole batch in ONE message**, then the red runs one after the other, each
  against its own worktree: `run-checks.sh {manifest} red {worktree}`.
- **Builders for the whole batch in ONE message**, the normal dispatch with the worktree as repo
  path plus two lines: `Batch: {the other TASK-IDs}, never touch their files` and `Push: deferred,
  after GO commit but skip Step 8 and report push-pending-consent; Steps 9 to 9b still run`. Model
  per the ladder (standard tier in a repo that says `loopit: no fast tier`).
- **Gate each `ready` one after the other**, never concurrently, after SKILL.md step 4's report
  check and REAL-AI rule: `run-checks.sh {manifest} green {worktree} {HASH}`. A FAIL goes back to
  that builder as usual; the others wait at `ready`. Landing starts once every remaining member is
  green.
- **Proof of disjointness**, once all members are green: `git -C {wt} status --porcelain` for each,
  minus the INSTALLED check files. Overlap = the later task in queue order drops out: land the
  other members, then re-run it ALONE in the main tree (fresh builder, `Attempt` +1, its worktree
  diff and handoff note as grounding). Nothing is prefetched while it runs.
- **Land in queue order, one at a time.** For each: `git -C {wt} add -A -- . ':!{each INSTALLED
  path}' && git -C {wt} diff --cached --binary HEAD > ~/.claude/loopit-par/{repo-basename}-{crc}/{TASK-ID}.patch`.
  Never write the patch into the manifest folder: `run-checks.sh` hashes every non-log file there,
  so a patch beside `checks.json` reads as TAMPERED. Note the main HEAD,
  then `git apply --check {patch} && git apply --3way {patch}`: a failed check leaves the tree
  untouched and counts as overlap (above). Run the green gate again in the MAIN tree, then GO the
  same builder (SendMessage) with "your repo is now {main tree}, your Baseline HEAD is now {the
  noted HEAD}; re-run Step 4 and the Step 5 review there first". That noted HEAD is also the one
  SKILL.md's dead-builder check compares against. The commit-review gate keys on the session's
  cwd, so a review any worktree builder ran counts for the main tree: the landing builder's report
  must show a Step 5 review run after this GO, else answer `FAIL-REPORT`. Then Step 10 for that
  task, then the next one.
- **One push per batch.** After every commit of the batch lands, ask the user once (repos that need
  push consent), push them together, then check CI once. A push per task would deploy each time.
- **A batched builder that needs a fork, a handoff or a block** leaves the batch: land the others
  first, then handle it alone the normal way, with its worktree diff and handoff note as
  grounding. Nothing is prefetched while it runs.
- **Cleanup is the user's call**: list the worktrees in the End report and ask before any
  `git worktree remove`.
- Report line per task: `BATCH: {other TASK-IDs}, landed {position}/{members at dispatch}` or
  `BATCH: alone (overlap|conflict|left)`, plus `prefetched` when it was dispatched during a landing.
  Judge the rule on wall-clock saved vs re-runs caused (grep `BATCH:` in the run logs) before widening it.
