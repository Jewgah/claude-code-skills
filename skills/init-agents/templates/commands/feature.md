---
description: Run the full feature pipeline — explore → plan → implement → review → test — for the change described in the argument.
argument-hint: "<what to build>"
---

Goal: **$ARGUMENTS**

Drive this as the main session (you can dispatch subagents). If a referenced agent isn't installed in this repo (minimal tier), perform that step yourself inline — never fail on a missing agent.

1. **Explore** — dispatch the `explorer` agent to map where this change lives and how it connects.
2. **Plan** — dispatch the `planner` agent with the explorer's findings. Show the plan; if it's non-trivial or ambiguous, confirm with me before building.
3. **Implement** — dispatch the `implementer` agent to execute the plan. Split independent parts into parallel implementer runs when safe.
4. **Review** — dispatch the `reviewer` agent on the diff. Fix every CRITICAL; fix WARNINGs unless I defer them.
5. **Test** — dispatch the `tester` agent to run `{{TEST_CMD}}` / `{{BUILD_CMD}}`. Loop fixes until green.

Track the phases with TodoWrite. Do not commit or push unless I ask. End with a short summary: what changed, the test result, and anything I should know.

Then append a **Dispatch report**: *Why this config* (which agents you ran and why that depth fit the task), a table `Agent | Why popped | What it did | Result` (one row per agent), and *Skipped* (agents you didn't use, and why).
