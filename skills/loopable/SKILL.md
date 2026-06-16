---
name: loopable
description: Find recurring work worth automating, then take the top candidate through the full delivery flow — plan, /review-plan, implement, /review-deep, fix all findings, commit, and file a ticket in ~/Downloads/tickets/{project}/.
disable-model-invocation: true
argument-hint: "[focus, '#N' to pick a candidate, or 'scan' for diagnose-only]"
---

# Loopable — find what deserves a loop, then build it

You are an **automation scout and builder**. Input: $ARGUMENTS (focus area, a candidate number like `#2`, or `scan` for diagnose-only).

## Phase 1: Collect recurrence signals

Run these, skipping any that don't apply:

1. **Git history**: `git log --oneline -200 --pretty='%ad %s' --date=short` — cluster commit subjects; repeated verbs/patterns = recurring chores. Ignore one-day bursts; look for rhythm across days/weeks.
2. **Manual scripts**: `scripts/`, `*.sh`, `*.command`, Makefile targets, `package.json`/`composer.json` scripts run by a human on a rhythm.
3. **Claude usage**: `~/.claude/skill-usage.log` filtered to this project + repeated user prompts in `~/.claude/projects/<encoded-cwd>/*.jsonl`.
4. **Docs & memory**: CLAUDE.md / roadmap.md / README chores ("every", "before each", "remember to"); global rules the project violates (e.g. missing roadmap.md).
5. **Already automated**: husky hooks, launchd, cron, GitHub Actions, `.claude/settings.json` hooks — exclude these; flag near-duplicate existing skills.

## Phase 2: Score, rank, pick

Score candidates on **frequency** (3+ occurrences), **determinism**, **verifiability** (machine-checkable success), **blast radius**. Map each to ONE mechanism: `/loop`, `/schedule`, hook, launchd/cron + `claude -p`, workflow, or plain script (no LLM needed).

Print the ranked table:

| # | Recurring work | Evidence | Mechanism | Trigger + success check | Risk gate |

If $ARGUMENTS is `scan`, STOP here (report only). Otherwise continue with the top candidate, or the one named `#N`.

**Hard gate**: if the chosen candidate automates deploys, pushes, or production-DB changes — STOP and ask for explicit consent before Phase 3.

## Phase 3: Plan + review the plan

Write a short implementation plan (files to create/edit, trigger, success check, rollback). Run the `/review-plan` skill on it and apply its feedback before touching anything.

## Phase 4: Implement

Build the automation exactly as planned (hook in settings.json, script, skill, schedule, etc.). Keep it minimal — no features beyond the plan.

## Phase 5: Deep review + address ALL findings

Run the `/review-deep` skill on the changes. **Fix every issue it raises** — do not just list them. Re-verify after fixing; repeat until clean or a finding is explicitly accepted with a one-line justification.

## Phase 6: Commit + ticket

1. Commit the automation with a clear message (review already done in Phase 5). Do NOT push — pushing is a separate, explicit step.
2. Write a ticket for the change as markdown (summary, what changed, how to verify, rollback) and save it to `~/Downloads/tickets/{repo-folder-name}/YYYY-MM-DD-<slug>.md` (create the folder if missing).

## Phase 7: Report

End with: the ranked table, what was implemented (files + mechanism), review-deep findings and how each was addressed, the ticket path, and a short **Not worth automating** list so weak candidates aren't re-proposed next run.

## Do NOT

- Do NOT automate deploys, pushes, or production-DB changes without explicit consent each time.
- Do NOT pad the candidate table; 3 strong candidates beat 10 weak ones. If nothing recurs enough, say so and stop after Phase 2.
- Do NOT skip or merely summarize review-deep findings — each one gets fixed or explicitly accepted.
- Do NOT push or deploy anything; the flow ends at local commit + ticket file.
