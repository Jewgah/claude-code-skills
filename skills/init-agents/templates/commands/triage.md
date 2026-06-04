---
description: Triage a bug report (PDF / markdown / text) — extract the issues, prioritize, then run the fix pipeline per issue.
argument-hint: "<path to report, or a pasted list>"
---

Source: **$ARGUMENTS**

Run this as the main session (you can dispatch sub-agents). If a referenced agent isn't installed (minimal tier), do that step yourself inline.

1. **Read the report** — if `$ARGUMENTS` is a file path (PDF, `.md`, `.txt`), read it (the Read tool handles PDFs); if it's a pasted list, use it as-is. If empty, ask me for the path.
2. **Extract & list** — turn it into a checklist with TodoWrite: one item per distinct issue, each with a short title + the reported symptom + any repro/location hints.
3. **Triage** — tag each issue `CRITICAL` / `HIGH` / `NORMAL` / `LOW`. Flag anything ambiguous or needing a product decision as **needs-info** and do NOT fix it — surface it for me to resolve.
4. **Fix loop** — in priority order, for each actionable issue: dispatch `explorer` (locate + root cause) → `implementer` (minimal fix) → `tester` (`{{TEST_CMD}}`); add a `reviewer` pass if the fix is risky. Update each todo as you go. If there are many issues, auto-handle `CRITICAL` + `HIGH` and pause to ask before `NORMAL`/`LOW` — unless I said do all.
5. Don't commit or push unless I ask.

End with a **triage summary table**: `Issue | Severity | Status (fixed / deferred / needs-info) | Root cause + fix (path:line)`. Then append the **Dispatch report**: *Why this config*, the per-agent table `Agent | Why popped | What it did | Result`, and *Skipped*.
