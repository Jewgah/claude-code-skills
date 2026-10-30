# Loopit: fork on hard tasks

Read by the orchestrator only when SKILL.md sends it here.

Two fresh-context builders attack the same task in parallel, and the acceptance gate picks the
winner. Handoffs already give a stuck task a fresh context; this adds a second, independent attempt,
only where a task has proven hard.

- **Hard = evidence, never a guess from the task line.** Fork when a standard-tier builder (a) fails
  gate round 2, or (b) returns `STATUS: blocked` for a TECHNICAL reason. Never on a block for a
  product decision, a consent, a client answer or a check-dispute: no branch can fix those. A
  `(fork)` tag in the task's notes forks from the first dispatch. A fast-tier failure escalates to
  the standard tier first.
- **Requires a gate**: git mode and checks installed (`red-ok`). No checks means no scorer, so no
  fork; take the normal path.
- **Once per task, 2 branches, standard tier.** Commit nothing. Snapshot the current tree, failing
  work included (it IS the inherited workspace): for b in a, b, `git worktree add
  ~/.claude/loopit-forks/{repo-basename}-{crc}/{TASK-ID}-{b} HEAD`; then, only if `git status
  --porcelain` is non-empty, `git stash push -u -m loopit-fork-{TASK-ID}` and in each worktree
  `git stash apply stash^{/loopit-fork-{TASK-ID}}` (a clean tree has nothing to carry: skip both, or
  `apply` picks up an unrelated stash). The main tree stays clean.
- **Dispatch both builders in ONE message** (they run concurrently), or one after the other when
  Step 0 found a compose stack (two `/battle-test` stacks fight over host ports and fail the gate on
  noise). The normal dispatch with the worktree as repo path, same intents, `EXISTS` and HASH,
  `Attempt: 3/3` (reads the note first, never hands off), an extra `Fork: {a|b}` line, the failing
  builder's handoff note, the last FAIL lines, and "a previous attempt failed here; you may keep or
  discard its approach". Each stops at `STATUS: ready`, never commits.
- **Gate each `ready` one after the other, never concurrently** (both write logs into the same
  manifest folder): `run-checks.sh {manifest} green {worktree} {HASH}`. First `green-ok` wins; a
  second branch still running is left to finish and ignored.
- **Winner into the main tree**, WITHOUT the check files `green-ok` left installed there (its
  `INSTALLED` lines; carried over they make the main gate return `collision`): `git -C {winner}
  add -A -- . ':!{each INSTALLED path}' && git -C {winner} diff --cached --binary HEAD >
  {manifest dir}/fork-win.patch`, then `git apply {that patch}` in the main repo (new files
  included). Dispatch a fresh builder there with `Attempt: 3/3`, `Fork: win` and the winner's
  report: it re-runs Steps 4 to 6 on the full diff (the commit-review gate only accepts a review run
  from this repo) and returns ready. Gate it as round 3, the last: `green-ok` gets GO as usual, a
  fail goes `[~]` blocked.
- **No winner**: `[~]` blocked; name both worktrees and the stash in the End report.
- **Cleanup is the user's call**: list the worktrees (`git worktree remove`) and the
  `loopit-fork-{TASK-ID}` stash in the End report and ask; never remove them unasked.
- Report line: `FORK: {trigger}, winner {a | b | none}`. Judge the rule on its win rate (grep
  `FORK:` in the run logs; `stats.sh` does not parse it) before widening it.
