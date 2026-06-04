---
description: Diagnose and fix a bug — reproduce → locate → root-cause → fix → test.
argument-hint: "<bug description / repro>"
---

Bug: **$ARGUMENTS**

If a referenced agent isn't installed in this repo (minimal tier), do that step yourself inline — never fail on a missing agent.

1. **Reproduce / locate** — dispatch the `explorer` agent to find the responsible code and trace the path. If a repro command exists, run it.
2. **Root cause** — identify the actual cause, not the symptom. State it in one line before fixing.
3. **Fix** — dispatch the `implementer` agent for the minimal correct fix.
4. **Verify** — dispatch the `tester` agent to run `{{TEST_CMD}}` and confirm the bug is gone and nothing regressed.
5. **Guard** — quick `reviewer` pass if the fix touches anything risky.

Report the root cause, the fix (`path:line`), and the test result. Don't commit unless I ask.

Then append a **Dispatch report**: *Why this config* (which agents you ran and why that depth fit the bug), a table `Agent | Why popped | What it did | Result` (one row per agent), and *Skipped* (agents you didn't use, and why).
