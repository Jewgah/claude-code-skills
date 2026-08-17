---
name: battle-test
description: >
  Run the frontend and backend checks that CAN actually be run for the current
  change, then report what ran, a battle-tested score out of 100, and the checks
  that still need a human. Use after implementing a feature or a bugfix and
  before committing it: "test this", "run the tests", "did I break anything",
  "how solid is this change", "what still needs manual testing", "teste ça",
  "est-ce que c'est bien testé". Runs the repo's own tooling only, never a new
  framework. It reports; it never commits, pushes, or deploys.
argument-hint: "[frontend | backend] [staged | unstaged | last-commit]"
---

# Battle-test the current change

Decide what can be run, run it, score how well the change is actually covered, and hand back the
checks a human still has to do. `$ARGUMENTS` narrows the side (`frontend`/`backend`) and the git
scope; blank means both sides, all pending changes.

## Phase 1 - Triage (before running anything)

1. Resolve the scope: `staged` -> `git diff --cached`, `unstaged` -> `git diff`, `last-commit` ->
   `git diff HEAD~1` (empty tree if there is no parent), blank -> both diffs. **Add untracked files**
   (`git ls-files --others --exclude-standard`): a brand-new module is invisible to `git diff` and
   is exactly the code least likely to be covered. Not a git repo (`git rev-parse --git-dir` fails)
   -> fall back to the files the user names, and say the scope came from them, not from git.
2. **Empty-diff guard**: no changes in scope -> say so and stop. Do not run a suite for nothing.
3. Detect what the repo actually has (`package.json` scripts, `composer.json`, `Makefile`,
   `pytest`/`cargo`/`go`, a dev script, a compose file, an emulator), then sort every check that
   matters **for this diff** into three buckets and print them before executing anything:
   - **AUTO** - runnable now, non-destructive, no credentials: test/typecheck/lint/build scripts,
     and single-file language checks (`php -l` through the Docker wrapper, `tsc --noEmit`,
     `node --check`).
   - **BOOTABLE** - runnable after starting something the repo owns: dev server, Docker stack,
     emulator. Start it, use it, stop only what this run started.
   - **MANUAL** - impossible here: prod or client credentials, a real payment, a real device, a
     third-party dashboard, an email or message actually arriving, a visual judgment call, or a
     production DB change.

Bucket by what the diff touches, not by what the repo owns. A backend-only diff earns no browser
pass.

4. **Blast-radius preflight, before the first command runs.** A check that can reach real data or a
   real person is NOT auto, whatever the script is named. The default is refuse, not try:
   - **Read the env the command will actually use** (`.env*`, `firebase.json` / `.firebaserc`, the
     compose file, the test config) before running it. Pointed at a production project, a live API
     key, a shared staging DB, a real SMTP host or a third-party webhook -> **MANUAL**. Prefer the
     repo's emulator or test env; if the only env available is the real one, do not run it.
   - **Anything that reaches a human** (email, SMS, WhatsApp, push, a call to a partner API that
     bills or writes) is MANUAL even in "test mode", unless the repo pins a sandbox you verified.
   - **Anything that mutates a store**: seed, reset, migrate, truncate, `--force`, fixtures that
     drop collections. MANUAL unless it provably targets a local throwaway you started.
   - **Rate-limited or paid third parties** (Apollo, LinkedIn, HubSpot, OpenAI, a payment provider):
     MANUAL. Burning a client's quota to raise a score is not a trade worth making.
   When you cannot tell which env a command uses, it is MANUAL. State the reason in one line and
   move on; an unrun check costs points, and that is the correct outcome.

## Phase 2 - Backend

Run AUTO first, then BOOTABLE. Keep the tail of a passing command, the full output of a failing one.
PHP goes through the Docker wrapper; if Docker is down, that check moves to MANUAL instead of being
skipped silently.

If the diff adds non-trivial logic that no suite covers, write ONE minimal runnable assertion for it
(the smallest thing that fails if the logic breaks), run it, and say you added it.

## Phase 3 - Frontend (only when the diff touches UI)

Delegate to `/frontend-verify`; do not reimplement browser driving. Cover its two gaps first:

- **Preflight**: `playwright-cli --help`. Missing -> the browser pass goes to MANUAL with the
  install command, the run continues.
- **Which backend the page will talk to, checked before booting anything.** A dev server is a
  browser pointed at whatever its env says. If that env is the live project (a real Firebase
  project id with no emulator flag, a prod API base URL, real keys), the browser pass is **MANUAL**:
  loading a route reads, writes and authenticates against real user data. Boot it only against the
  repo's emulator or sandbox env, and only by setting the flag the repo already provides (for
  example `VITE_USE_EMULATORS=true` with `firebase emulators:start`), never by editing `.env`.
  Cannot tell which backend it hits -> MANUAL.
- **Dev server**: `/frontend-verify` never starts one. Probe the base URL; if nothing answers, start
  the repo's dev script in the background and poll, never sleep-and-hope:
  `timeout 30 bash -c 'until curl -sf http://localhost:3000 >/dev/null; do sleep 1; done'`.
  Stop it by killing the port listener only: `lsof -ti:3000 -sTCP:LISTEN | xargs kill`. Never
  `pkill -f node|vite|next`, it can kill this session. A server that was already up stays up.

## Phase 4 - Score out of 100

Start at 0, add only what was observed:

| Signal | Pts |
|---|---|
| The changed code path was executed at all, not merely compiled or linted | 30 |
| An automated assertion covers the specific new behaviour | 25 |
| Every error/edge branch the diff introduces was exercised | 15 |
| The existing suite ran in full and is green | 15 |
| The real surface was driven end to end (browser pass, or a real API call) | 10 |
| Nothing in MANUAL is load-bearing for the change to be correct | 5 |

Green-but-shallow scores low: a passing typecheck with the new function never called is <= 30. Never
round up to be encouraging.

## Phase 5 - Report

```
Ran: 4 checks (3 green, 1 red)
  OK  pnpm typecheck, pnpm lint, vitest (28 passed)
  RED pnpm test - cart.spec.ts:41 expects the old status value
Battle-tested: 45/100
  The new webhook branch never ran; only the happy path is asserted.
Manual (2):
  1. Pay with a real card in Stripe test mode, confirm the order flips to paid.
  2. Apply the migration by hand before this ships.
```

Red is stated as red with its output, never softened. No MANUAL items -> `Manual: none`. A check
that was skipped goes to MANUAL: silence reads as "checked and fine", which is a lie. Mention the
disposable `.frontend-verify/` directory if a browser pass wrote one.

## Do NOT

**The hard rule: this skill must never change real data or reach a real user.** A check that can
only run against the real thing does not run. It goes to MANUAL, it costs points, and that is the
right answer. A lower score is always cheaper than a client's data.

- Never run anything that writes to a production database or a live client environment. No SQL
  against a production DB over SSH, ever; DB changes go to MANUAL to be applied by hand. A
  `*deploy*.sh` wrapper goes to MANUAL too, whatever it claims to test.
- Never point a check at prod to make it runnable. Do not edit `.env`, swap a config, or export a
  credential to get a suite to pass. Run it in the repo's sandbox or not at all.
- Never commit, push, or deploy. This skill reports.
- Never leave a process running that this run started.
- Never claim a check passed that was not executed.
- No new test framework, config file, CI wiring, or fixtures. Use what the repo already has.
