# Loopit: build up to three tasks in parallel

Read by the orchestrator only when SKILL.md sends it here. The slow part of a task is the
builder's Steps 1 to 6; landing (commit, push, Step 10) stays one task at a time, in queue order.

- **Batch = up to 3 tasks, never more.** Each in the same git repo, with checks (`has_runner:
  yes`), not tagged `(fork)` or `(decision)`, no `[!]` open, and no compose stack found in Step 0
  (stacks fight over host ports). Anything else runs alone.
- **Pick from the next 8 runnable `[ ]` tasks, not only the next ones.** The first runnable task is
  always in the batch; add the next tasks, in queue order, whose files are disjoint from every task
  already in it. Never take a task that depends on one it would jump: its line or `>` notes name an
  earlier task's ID, ticket, or a file that earlier task will touch. A skipped task is not blocked;
  it is first in line for the next batch.
- **Disjoint files, predicted then proved.** Before batching, name the files each task will touch
  (task line, its `>` notes, one grep). Any shared file, or a shared generated one (a lockfile, a
  snapshot, a rules file plus its proof, a doc both would edit): not in the same batch. The
  prediction is a guess, so the proof comes after Step 6 (below).
- **Prefetch while landing.** Once every task of a batch is green and only landing remains (commit,
  push, Step 10), start the next batch now, in fresh worktrees off the current HEAD, counting the
  tasks still landing as members for the disjointness test. Live builders never exceed 3: the
  prefetch takes only the slots freed by tasks past Step 10, so it grows as each one lands. If the
  first runnable task overlaps a task still landing, wait for that task's Step 10 instead of
  skipping it. Patches apply with `--3way` like any other. Never prefetch while a `[!]` is open or
  a push was refused.
- **One worktree each**: `git worktree add ~/.claude/loopit-par/{repo-basename}-{crc}/{TASK-ID} HEAD`.
  A worktree has no gitignored files, so before dispatch symlink the dependency folders the verify
  commands need (`node_modules`, `functions/node_modules`, `vendor`...) and copy the `.env*` files
  from the main tree. Never `npm install` into a symlinked folder.
- **Check-writers for the whole batch in ONE message**, then the red runs one after the other, each
  against its own worktree: `run-checks.sh {manifest} red {worktree}`.
- **Builders for the whole batch in ONE message**, the normal dispatch with the worktree as repo
  path plus two lines: `Batch: {the other TASK-IDs}, never touch their files` and `Push: deferred,
  after GO commit but skip Step 8 and report push-pending-consent; Steps 9 to 9b still run`. Model
  per the ladder (`opus` in a repo that says `loopit: no fast tier`).
- **Gate each `ready` one after the other**, never concurrently, after SKILL.md step 4's report
  check and REAL-AI rule: `run-checks.sh {manifest} green {worktree} {HASH}`. A FAIL goes back to
  that builder as usual; the others keep going.
- **Proof of disjointness**, once a task is green: `git -C {wt} status --porcelain`, minus the
  INSTALLED check files, against every other batch member's. Overlap = the later task in queue order
  drops out: land the other members in queue order, then re-run it ALONE in the main tree (fresh builder,
  `Attempt` +1, its worktree diff and handoff note as grounding).
- **Land in queue order, one at a time.** For each: `git -C {wt} add -A -- . ':!{each INSTALLED
  path}' && git -C {wt} diff --cached --binary HEAD > ~/.claude/loopit-par/{repo-basename}-{crc}/{TASK-ID}.patch`,
  then `git apply --3way {that patch}` in the main tree. Never write the patch into the manifest
  folder: `run-checks.sh` hashes every non-log file there, so a patch beside `checks.json` reads as
  TAMPERED. A conflict = same as overlap above. Run the green gate again in
  the MAIN tree, then GO the same builder (SendMessage) with "your repo is now {main tree}; re-run
  Step 4 and the Step 5 review there first". The commit-review gate keys on the repo root, so a
  review run in the worktree does not count. Then Step 10 for that task, then the next one.
- **One push per batch.** After every commit of the batch lands, ask the user once (repos that need
  push consent), push them together, then check CI once. A push per task would deploy each time.
- **A batched builder that needs a fork, a handoff or a block** leaves the batch: land the others
  first, then handle it alone the normal way.
- **Cleanup is the user's call**: list the worktrees in the End report and ask before any
  `git worktree remove`.
- Report line per task: `BATCH: {other TASK-IDs or -}, landed {k}/{n} | alone (overlap|conflict|left)`,
  plus `prefetched` when it was dispatched during a landing. Judge the rule
  on wall-clock saved vs re-runs caused (grep `BATCH:` in the run logs) before widening it.
