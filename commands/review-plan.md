---
description: Critically review the current plan/approach before implementing — assumptions, gaps, blast radius, deploy safety
argument-hint: "[optional: the plan or approach to review]"
---

Locate the plan to review, in this priority order, and state which source you used in one line before starting:
1. If `$ARGUMENTS` is non-empty, review that text as the plan.
2. Else, the active plan-mode plan — read the most recently modified file in `~/.claude/plans/` (`ls -t ~/.claude/plans/*.md | head -1`).
3. Else, the approach described in my previous message.

Critically review the current plan or approach before proceeding with implementation:

1. **Restate the goal**: What exactly are we trying to achieve? Strip away assumptions and re-read the original request.

2. **Challenge assumptions**: For each step in the plan:
   - What are we assuming to be true? Is it actually true?
   - Read the relevant code/docs to verify — don't rely on memory or guesses
   - Are we solving the right problem, or a symptom?

3. **Error scenario audit**: Walk through every failure path:
   - What happens if the input is missing, malformed, or unexpected?
   - What happens if an external service (API, DB, auth) fails or times out?
   - What happens if this runs concurrently or out of order?
   - What edge cases could break this silently (empty arrays, null values, race conditions)?

4. **Blast radius check**:
   - What else could this change break? Search for all callers/consumers of modified code
   - Are we changing a shared interface, type, or contract?
   - Could this affect other environments (prod, staging, other projects)?

5. **Simpler alternative**: Is there a simpler way to achieve the same result?
   - Are we over-engineering or adding unnecessary abstraction?
   - Could we use an existing utility, pattern, or library instead?
   - Would a 3-line fix do what a 50-line refactor does?

6. **Omission check**: Audit what the plan does NOT mention:
   - Tests, rollback path, data migration, observability/logging
   - The "do nothing" baseline — is this change even necessary?
   - List each gap explicitly.

7. **Deploy & reversibility**: If the plan touches a server or DB:
   - One-way door (hard to reverse) or two-way (easy)? Call it out.
   - Servers others edit in place: did we **pull before deploy**, and is the prod config (`.htaccess`, etc.) being **merged, not overwritten**?
   - DB change with no migration system: is the hand-applied DB step written down and reversible?

8. **Devil's advocate**: Before the verdict, argue the strongest case that this plan is *wrong or unnecessary*. What would a skeptic who wants to kill this plan say?

9. **Verdict**: Summarize findings as:
   - **Confirmed**: Assumptions that hold up after verification
   - **Invalidated**: Assumptions that were wrong — with corrections
   - **Risks**: Remaining concerns or edge cases to handle
   - **Riskiest assumption**: the single assumption that, if false, sinks the plan
   - **Call**: Go / Adjust / Rethink (one word + one sentence why)
