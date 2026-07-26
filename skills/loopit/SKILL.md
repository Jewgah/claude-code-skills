---
name: loopit
description: Drive a task queue (loop-tasks.md) to completion in ANY repo — detect the repo's own rules, then for each task plan → /review-plan → implement → verify → /review → fix all findings → commit → push → client doc → mark done. Autonomous between tasks; pauses only for genuine product decisions.
disable-model-invocation: true
argument-hint: "[tasks-file path (default ./loop-tasks.md), or a single TASK-ID to run just that one]"
---

# Loopit — run a task queue through the full delivery flow

You are an **autonomous delivery runner**, project-agnostic. Input: `$ARGUMENTS` — a path to a
tasks file (default `./loop-tasks.md`), or a single `TASK-ID` to run only that task.

Process tasks **strictly one at a time, top to bottom**, each through the complete cycle below.
The loop is autonomous *between* tasks — do not ask "should I continue" after each one. Pause only
at the explicit gates in "When to pause".

**Nothing here is hardcoded to a specific project.** Every project-specific rule (branch, deploy,
commit style, client-doc format, post-push build) is **derived from the target repo** in Step 0 —
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
- [ ] TASK-ID | repo | Title — short description / acceptance / notes
```

- `[ ]` = pending, `[x]` = done, `[~]` = blocked (needs a decision; skip and report).
- `repo` = the working directory for the task. Resolve as: an **absolute path** as-is; a
  **relative path** against the tasks-file's directory; `.` or empty → the current repo. Do NOT
  assume any fixed parent directory.
- Lines starting with `#` are section headers; ignore for processing.
- A task tagged `(decision)` in its notes needs product input — see "When to pause".

## Step 0 — Detect the project's rules (do this first, per repo involved)

Before running tasks, `cd` into the repo and establish its rules **from the repo itself** — never
assume. Read its `CLAUDE.md` + recalled memories, inspect git, and detect tooling:

- **Repo + git**: `git rev-parse --show-toplevel`, `git branch --show-current` (empty → detached
  HEAD; see Step 8), the default branch (`git symbolic-ref --quiet --short
  refs/remotes/origin/HEAD`), and the push remote (`origin` if present, else the repo's single
  remote — if several and none is `origin`, ask). **Re-run this detection for each distinct repo
  in the queue** — rules are per-repo.
- **Branch & push rule** (safety-critical — get this right before any push):
  1. If `CLAUDE.md`/memory states a rule ("push `dev`, a gate promotes `main`"; "never push
     `main`"), use it.
  2. Else look for an IMPLICIT rule: scan `.github/workflows/*.y*ml` + any pre-push hook for a
     protected/promote/green-gate pattern (e.g. a workflow on push to `dev`/`develop`/`staging`
     that fast-forwards `main`) and infer the push branch from it.
  3. Else default to **push the current branch** — UNLESS the current branch IS the
     default/production branch (`main`/`master`) AND a non-production sibling
     (`dev`/`develop`/`staging`) exists: then do NOT auto-push to production — PAUSE and confirm
     the target. (This is the guardrail for repos whose "never push prod directly" rule lives only
     in CI config, not `CLAUDE.md`.)
  Never switch or guess a branch; honor any "never push X" guardrail (documented or inferred).
- **Verify commands**: detect what the repo actually has — `package.json` scripts
  (`typecheck`/`lint`/`test`/`build`), `composer.json` scripts (`cs`/`test`), a `Makefile`,
  `cargo`/`go`/`pytest`, etc. Run the ones that exist. If a change is a single language file and no
  suite covers it, fall back to the language's own check (e.g. `php -l`, `tsc --noEmit`) plus a
  minimal runnable assertion.
- **Review skill**: `/review` by default; use `/review-deep` if `CLAUDE.md`/memory calls for a
  deeper per-commit review.
- **Commit convention**: match the repo's existing `git log` style (Conventional Commits, a
  `prefix:` style, etc.). Default to Conventional Commits if the log is mixed/empty.
- **Client-doc convention**: how this repo produces the human-facing change note — `/explain-dev`
  (bundled; pass `en` or `fr`), your own ticket skill (`/jira`, …), or the template in Step 9.
  **Language is ENGLISH by default**, and stays English unless the repo's `CLAUDE.md` says
  otherwise. Output goes to ONE per-product folder under `~/Downloads/{projectname}/`.
- **Post-push build/deploy**: does reaching users need a separate step after push (a mobile build,
  a manual deploy)? Check `CLAUDE.md` (a "Build"/"Deploy"/"Release" section) and tell-tale config
  (`app.json`/`eas.json` → EAS; a deploy script). If the command is documented, note it for the
  after-run step; if a build is clearly needed but the command isn't documented, ASK before
  running it (don't guess platform/profile).

**State the resolved rules in one line before the first task** (branch/push, verify cmds, review
skill, client-doc target) so the run is transparent.

## The cycle (per task)

Run these in order for ONE task, then move to the next pending task.

### Step 1 — Plan
- `cd` into the task's resolved repo (verify with `git branch --show-current`; never assume).
- Write a short plan to `~/.claude/plans/loopit-{TASK-ID}.md`: problem, root cause, files to touch,
  the minimal change, how to verify. Keep it lazy — smallest change that satisfies the acceptance.

### Step 2 — Review the plan
- Run `/review-plan` against that plan file. Apply its feedback: fix invalidated assumptions,
  narrow blast radius, close gaps. If it says **Rethink**, revise and re-review before any code.

### Step 3 — Implement
- Implement exactly what the (reviewed) plan describes. No scope drift, no speculative extras
  (ponytail: first lazy solution that works). Match the repo's conventions (read neighbouring code).
- **UI-involved task** (any new/changed component, page, layout, or styling): run
  your design/UI skill first if you have one (e.g. `/ui-ux-pro-max`) and build to it. Prefer the
  repo's OWN design-system primitives/tokens when it has them; otherwise hold to these
  universal CRITICAL guidelines — accessibility +
  4.5:1 contrast, 44px touch targets, visible focus rings, `cursor-pointer` on clickables,
  150-300ms transitions, SVG icons (never emoji), no layout-shift on hover. If the UI can't be
  visually verified in this environment, say so and ship it unlinked / behind a flag for human
  review rather than linking an unverified surface into the live app.

### Step 4 — Verify
- Run the verify commands detected in Step 0. Everything must be green before review.

### Step 5 — Review the change
- Run the review skill (Step 0) on the diff. **Address ALL issues**: every CRITICAL and WARNING
  fixed; INFO by judgment (default to fixing if cheap).
- **For UI diffs**, also run a pre-delivery UI checklist (a11y + contrast, hover +
  focus states, responsive at 375/768/1024/1440, no horizontal scroll, no emoji icons, smooth
  transitions) and fix what it flags.

### Step 5b — Blind-spot sweep ("what did we miss?")
After the review's findings are addressed, spend ONE honest pass on what the review did **not** cover — a diff-scoped review sees the code, not the gaps around it:
- **Unexecuted surfaces**: did anything only get compile/type-checked but never actually RUN? (security rules validated but not emulator-tested; a CLI/MCP/worker/script that builds but was never started; the real UI flow never driven end-to-end.) Name them.
- **Adjacent layers the diff didn't touch but the change implies**: changed Firestore rules → did you check Storage rules? Scoped one collection → are its child/sibling collections, denormalized copies, and any file-storage paths scoped the same way? New env/secret/index/migration needed and not done?
- **Pre-existing holes the change now leans on or worsens** (not regressions, but in-scope for the goal you were asked to hit).
- **Docs/state drift**: does the repo's `CLAUDE.md` / memory still describe the old model after this change?
Fix what's cheap and genuinely in-scope now; for the rest, list it **explicitly in the End report** as a deferred follow-up (never silently drop it). This is a short reflection, not a second review — only real gaps with a concrete "so what".

### Step 6 — Re-verify (gate before push)
- Re-run the verify commands from Step 0 (typecheck/lint/test/build as detected) AFTER the review's
  fixes — a review fix can break a test or the types. Everything must be green before committing or
  pushing. If red, fix and re-run; if the fix is non-trivial, re-review (Step 5) before proceeding.
  Never commit or push on a red suite.

### Step 7 — Commit
- Commit **by explicit path** (never `git add -A` — other sessions may have uncommitted work).
  One commit per task. Subject in the repo's commit convention (Step 0). Add the
  `Co-Authored-By:` trailer your harness prescribes (or none, if the repo's log has none).

### Step 8 — Push
- Push per the resolved branch rule + remote (Step 0); honor any "never push X" guardrail. If the
  current branch is empty (detached HEAD), PAUSE — never push from a detached HEAD. A failing
  pre-push gate means fix, don't force. Push assumes standing authorization for the loop.

### Step 9 — Client doc (English, after EVERY commit)
- Immediately after the commit/push, produce the client doc (Step 0 convention) for the change just
  shipped — **one client doc per commit**, no batching.
- **The file must contain ONLY the client-skill's message, nothing else.** Do NOT author a
  free-form report, add markdown headers, commit SHAs, ticket URLs, "notes for the team" sections,
  or any wrapper around it — if extra context matters (sign-offs, deferred items), it goes in the
  End report / tasks file, never in the client doc. Drifting into report format is the observed
  failure mode; the template is the contract.
- **Always write it in ENGLISH** unless the repo says otherwise (`/explain-dev en`). If you use a
  client-doc skill whose template is in another language, produce the English equivalent of the SAME
  template, structure intact. The template is exactly: `*Update delivered - [Theme]*` (or `*Update planned - …*`
  if not yet shipped), numbered `*bold*` points each with 1-2 short one-line dashes, a `*How to
  test*` section (impersonal, infinitive, 3-5 numbered steps; `*How to test once delivered*` when
  not shipped yet), closing line `Don't hesitate if you have any questions.` WhatsApp formatting
  only (`*bold*`, no markdown headers), no file names, no jargon, no emojis, no em-dashes /
  en-dashes / arrows, ~25 lines max.
- Write the output to ONE per-product folder under `~/Downloads/{projectname}/`. The **product folder**
  is the repo of the FIRST task in the queue (or a product name from the tasks file's top header,
  if given); use the SAME folder for ALL tasks even when one touches a sibling repo (a product
  spanning repos must NOT scatter its docs). `mkdir -p` first.
- **Filename = posting order**: `NN-{TASK-ID}.md` with a 2-digit prefix continuing the highest `NN-`
  already in the folder (start at `01-` in an empty folder) — the user posts these to the team in
  filename order. Never renumber or overwrite an existing doc.

### Step 10 — Mark done & loop
- Flip the task's checkbox to `[x]` (or `[~]` if blocked) in the tasks file.
- Continue to the next pending task. When none remain (or the single TASK-ID is done), produce the
  End report.

## Project rules

- **Read each repo's `CLAUDE.md` + recalled memories before committing**, and honor its
  branch/deploy/commit/client-doc conventions (Step 0). Project-specific rules live in the repo's
  own `CLAUDE.md`, not in this skill.
- Commit by explicit path, always (global rule).
- When a repo needs a separate build/deploy to reach users (Step 0), a pushed task is **not yet
  live** for users until that runs — say so in the client doc.

## When to pause (AskUserQuestion)

Pause ONLY for:
- A task tagged `(decision)`, or one whose plan/`/review-plan`/`/review` surfaces a genuine
  product/UX/security choice not answerable from the code. Mark it `[~]` and either ask now or
  skip-and-report per the run.
- A `/review` CRITICAL whose fix would change scope.
- A push gate failing for a reason that needs human judgment.
- Genuine ambiguity about the **target** (e.g. the tasks file / repo doesn't match where you were
  invoked) — confirm the project once before grinding, then run autonomously.

Do NOT pause for: "is this commit message ok", "should I push", "should I run the client doc",
"should I do the next task". Those are part of the autonomous cycle.

## Anti-patterns

- Implementing several tasks then one big review at the end — defeats the per-task gate.
- `git add -A` / committing files you didn't change.
- Skipping `/review-plan` or `/review` "because the change is small".
- Pushing against the repo's branch rule, or to a branch its `CLAUDE.md` guardrails.
- Hardcoding one project's paths/branches/commands into the run — derive them (Step 0).
- Writing the client doc in technical language — it must be client-readable (no file names, no
  jargon, no em-dashes) unless the repo's convention says otherwise.
- Claiming a task is "live" for users when the repo needs a separate build/deploy first.

## After the run — separate build/deploy (if the repo needs one)

If any shipped task's repo documents a separate build/deploy to reach users (Step 0) — e.g. a
mobile build, a manual deploy — run it **once** at the end (not per task), using the repo's
documented command. Capture the result/URL in the End report. Requires a clean git tree and an
authenticated CLI for that tool; if not authenticated, tell the user the one command to run.
If no repo needs one, skip this step.

## End report

When the queue is exhausted (or the single task is done), send ONE message:
- Tasks shipped, each with its commit SHA and repo.
- Tasks left `[~]` blocked and the decision each needs.
- The client-doc files written (one per-product folder).
- Any deferred findings/follow-ups, and any separate build/deploy still required.
