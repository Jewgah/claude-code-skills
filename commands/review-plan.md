---
description: Critically review the current plan/approach before implementing — assumptions, gaps, blast radius, deploy safety
argument-hint: "[optional: the plan or approach to review]"
---

Locate the plan to review, in this priority order, and state which source you used in one line before starting:
1. If `$ARGUMENTS` is non-empty, review that text as the plan.
2. Else, the plan file this conversation wrote or was handed (plan mode, or a path a caller named). Never fall back to the newest file in `~/.claude/plans/`: parallel sessions write there too, so it can be another session's plan. If no plan is identifiable, ask for it.
3. Else, the approach described in my previous message.

**State the plan file's path AND its first heading before reviewing**, so a wrong file is
visible immediately.

**Proportionality**: depth scales with blast radius. A one-line fix gets a one-paragraph
review; do not manufacture findings to fill the checklist — an honest "nothing found" on a
step is a valid answer.

Critically review the current plan or approach before proceeding with implementation:

1. **Restate the goal**: What exactly are we trying to achieve? Strip away assumptions and re-read the original request.

2. **Challenge assumptions**: For each step in the plan:
   - What are we assuming to be true? Is it actually true?
   - Read the relevant code/docs to verify — don't rely on memory or guesses
   - For the RISKIEST assumption, prefer a cheap runnable read-only check (a script, a
     query, a curl) over reading code when one exists — an executed proof beats an
     inferred one (e.g. run the exact DB query the plan relies on against a copy/prod
     read-only before betting the fix on it).
   - Are we solving the right problem, or a symptom?
   - **Does the plan ADD capability (a column, table, setting, endpoint, screen section)?
     Then it must already carry a measured "what already exists" section.** If it does not,
     that is a finding on its own: say so and run the lookup yourself before judging the rest.
     Do not accept "it does not exist" as a claim, accept it as a grep or a `COUNT(*)`.
     This is the check that turned two plans around in one afternoon: one was adding empty
     inputs beside fields populated on 203 rows out of 203, the other was creating a settings
     table next to an existing one. Both plans read as sound until the lookup was run.

2b. **Project-rules check**: grep the target repo's `CLAUDE.md` + recalled memories for
   project-specific rules the plan touches — branch/deploy gotchas, "new query ships its
   index in the same commit", i18n locale count, commit/dependency conventions. Cite each
   rule the plan interacts with and say whether it complies. (A missing-index rule
   violation shipped to prod precisely because no review step looked for repo rules.)

2c. **Root-cause / attribution audit** (when the plan — or the message/diagnosis it rests on —
   pins a fault, *especially* on an external party or vendor): (a) was OUR side of the flow
   inspected and the exact code path cited? Where an error *originates* is not where it is
   *caused*. (b) Is a "systemic" claim backed by ≥2 independent data points, not one case? (c) Has
   the "assume it IS us" devil's-advocate pass been run? If any answer is no, the attribution is
   unproven — flag it and demand the check before the plan proceeds. (Origin: a confident
   external-blame diagnosis shipped with none of these done.)

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
   - Servers that colleagues also edit in place: did we **pull before deploy**, is there **explicit consent this turn**, and is prod config (`.htaccess`, `.env`, vhost) being **merged, not overwritten**?
   - DB change with no migration system: is the hand-applied DB step written down and reversible?

8. **Devil's advocate**: Before the verdict, argue the strongest case that this plan is *wrong or unnecessary*. What would a skeptic who wants to kill this plan say?

9. **Verdict**: Summarize findings as:
   - **Confirmed**: Assumptions that hold up after verification
   - **Invalidated**: Assumptions that were wrong — with corrections
   - **Risks**: Remaining concerns or edge cases to handle
   - **Riskiest assumption**: the single assumption that, if false, sinks the plan
   - **Call**: Go / Adjust / Rethink (one word + one sentence why)
