---
name: review-deep
description: Deep multi-agent code review — parallel agents cross-check each other to catch critical bugs
argument-hint: "[scope: staged, unstaged, last-commit, branch/pr, or blank for all]"
---

# Deep Multi-Agent Code Review

Perform an exhaustive, multi-perspective code review using parallel agents that cross-check each other. This catches bugs that a single-pass review misses — especially race conditions, state inconsistencies, and cross-file dependency breaks.

> **When to use this vs. the others** — reach for `/review` for a fast single-pass pre-commit check (no subagents); use **this** for a risky local change you want stress-tested before it ships; use `/code-review` once it's a **GitHub PR** (it posts inline comments and scores confidence). This skill reviews the **local working tree** and prints to the terminal — it does NOT post to GitHub. If the change is already a PR, prefer `/code-review`.

## Step 1: Gather Changes

1. Determine scope from `$ARGUMENTS`:
   - "staged": `git diff --cached`
   - "unstaged": `git diff`
   - "last-commit": `git rev-parse HEAD~1 >/dev/null 2>&1 && git diff HEAD~1 || git diff $(git hash-object -t tree /dev/null)` (falls back to the empty tree on a repo's first commit)
   - "branch" / "pr": review the whole branch against its base. Detect the default branch robustly: `BASE=$(git merge-base HEAD "$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@' || echo main)" 2>/dev/null || git merge-base HEAD main 2>/dev/null || git merge-base HEAD master)`. If `BASE` is still empty (non-standard default branch), fall back to `git diff` and state which base you used. Then `git diff $BASE...HEAD`.
   - Otherwise: both `git diff` and `git diff --cached`
2. Run `git status` for context.
3. **Empty-diff guard**: if the chosen diff is empty, stop and report "No changes in scope to review" — do not launch agents.
4. Read the COMPLETE content of every changed file (not just the diff).
5. **Load conventions**: read the nearest `CLAUDE.md` (and any project review notes) so agents can flag convention violations — project-specific patterns, naming conventions, tenant-scoping rules — not just generic bugs. Pass the relevant conventions into each agent prompt.

## Step 1.5: Size the Review

Scale effort to the diff — a 3-line change must not spawn 12 agents. Measure with `git diff --shortstat` (use the same scope/base resolved in Step 1).

- **Tiny** (≤ ~20 changed lines AND ≤ 2 files, AND no new function/method/endpoint): genuinely trivial — a typo, rename, or one-liner. Skip the fan-out: run **one** Explore agent covering all focuses below, then verify its top 1–2 findings yourself by re-reading the code. No skeptic fan-out.
- **Normal/Large** (anything bigger, OR any diff that adds a function/method/endpoint/query): run the full Step 2 fan-out (all 4 agents) and the Step 3.5 skeptic stage as written. New behaviour always earns the deep path, even if the line count is small.

State which tier you picked and why before launching.

## Step 2: Launch 4 Parallel Review Agents

Launch all 4 Explore agents **in a single message** (parallel). Each agent gets:
- The full diff
- The list of changed files
- The relevant conventions loaded in Step 1
- A DIFFERENT review focus (below)

**Prepend this global instruction to every agent prompt:**
> "Report ONLY issues introduced or made reachable by THIS diff. Do not report pre-existing issues in unchanged code. For every finding give exact file:line and a concrete trigger path — no vague 'could be a problem' without a path."

### Agent 1 — Dependency & Impact Analysis
> "For every function, variable, status value, or field that was CHANGED or ADDED in this diff, find ALL other files in the codebase that reference it. For each dependency found, report: file path, line number, the code that references it, and whether the change could break or alter its behavior. Pay special attention to status values (e.g., payment_status, booking.status), database fields, and shared state. **Include test files among the references — a changed symbol referenced in a test signals coverage that may now be stale or broken.** Report every impact — do not skip anything you find."

### Agent 2 — Race Conditions, State & Data Safety
> "Analyze the changed code for: (1) Race conditions — can concurrent executions (cron jobs, API calls, webhooks) process the same entity simultaneously? Is there a TOCTOU guard (re-fetch before mutate)? (2) State consistency — if step N succeeds but step N+1 fails, is the system left in a recoverable state? What is the order of operations and is it safe? (3) Double-processing — can the same entity be processed twice, causing duplicate writes, double credits, or duplicate API calls? (4) Atomic operations — are read-modify-write patterns safe against concurrent modification? Report every finding with exact line numbers."

### Agent 3 — Logic, Edge Cases, Security & Tests
> "Review the changed code for: (1) Logic errors - wrong conditions, off-by-one, inverted checks, missing null/undefined guards (2) Edge cases - empty arrays, missing fields, zero values, falsy values that could cause unexpected behavior (3) Security - auth bypass, exposed secrets, missing permission checks, and **SQL injection: any string-concatenated or unparameterized SQL, or unescaped user input reaching the DB layer (especially hand-written SQL layers and hand-managed databases)** (4) Error handling - unhandled promise rejections, missing try/catch, errors that leave state inconsistent (5) Breaking changes - could this change break existing API contracts, UI behavior, or downstream consumers? (6) **Test coverage - does this diff add or change behavior without adding/updating a test? Does it change a signature, return shape, or status value that existing tests rely on (i.e. would break them)? Flag untested new branches and any test the change silently invalidates.** (7) **Observability - silent catches, errors swallowed without a log, failures with no context (ids, operation) to debug from, and secrets/PII written into logs.** Report every finding with exact line numbers."

### Agent 4 — Tenant Isolation & Data Boundary
> "Check whether this change can leak or cross-contaminate data between tenants. (1) Does any query, route, cache key, file path, or background job omit the tenant/workspace/org scope? (2) Can tenant A read or mutate tenant B's data through this change? (3) Is any global or shared state (singletons, static caches, module-level vars) populated per-tenant but reused across tenants? (4) Do new endpoints or permissions enforce the tenant boundary the same way existing ones do? Report every finding with exact line numbers. **If this codebase shows no sign of multi-tenancy (no tenant/workspace/org scoping anywhere in the data layer), reply 'N/A — single-tenant' immediately and stop.**"

## Step 3: Cross-Check & Consolidate

After all 4 agents return:

1. **Deduplicate** — merge findings that describe the same issue from different angles
2. **Cross-validate** — if Agent 1 found a dependency that another agent missed the implications of, flag it
3. **Escalate** — if multiple agents independently flagged the same area, escalate its severity
4. **Triage** — assign each finding a severity (CRITICAL/WARNING/INFO). Do NOT self-confirm here; verification happens in Step 3.5.

## Step 3.5: Adversarial Verification

The agent that found an issue is biased toward confirming it — so verify with fresh skeptics whose job is to *refute*.

1. Rank all CRITICAL + WARNING findings by severity, and split them into **self-evident** vs. **contestable**:
   - *Self-evident* — provable from the diff alone, where a skeptic would add nothing (textbook SQLi via string-concat, a hardcoded secret, an obviously dropped tenant filter). Confirm these yourself by re-reading the lines; don't spend an agent.
   - *Contestable* — severity or reachability is arguable (is the race real? is the cross-tenant path actually reachable? is this `continue` intentional?). These get a skeptic.
2. **Spend skeptic agents on the contestable findings — up to 8, one Explore agent each, launched in a single parallel message.** If more than 8 are contestable, batch the rest by file (one agent per file) so fan-out stays bounded.
3. **Log the split** — state how many findings were self-confirmed by re-read vs. skeptic-verified individually vs. batched (no silent caps).
4. Each skeptic gets this prompt:
   > "Claimed issue: {finding, with file:line}. Read the actual code and its surrounding context. Your job is to REFUTE this. Is it genuinely reachable? Is there a guard elsewhere that prevents it? Is the control flow being misread? Default to `refuted: true` unless you can prove the issue is real with a concrete trigger path. Output: `verdict` (confirmed|refuted), `trigger_path`, `confidence` (high|medium|low), `reasoning`."
5. Drop every finding a skeptic refutes. Only **confirmed** findings reach the report, each carrying its `confidence`. INFO findings skip this stage entirely (they show `Confidence: N/A`).

## Step 4: Produce Final Report

For each confirmed issue:

**[SEVERITY] Category — File:line**
Description of the issue and why it matters.
Confidence: high/medium/low (from Step 3.5; INFO findings show N/A)
Suggested fix (if applicable).

Severity levels:
- **CRITICAL**: Bugs, security holes, data corruption, money loss — must fix before shipping
- **WARNING**: Potential problems, edge cases, code smells — should fix
- **INFO**: Minor suggestions, style issues, improvements — nice to have

End with a **Summary**:
- Total issues by severity, and how many survived adversarial verification (with their confidence)
- Which agents found which issues (to show coverage), and how many findings were verified individually vs. batched
- Overall assessment (safe to ship / needs fixes / needs major rework)
- The single most important thing to address

If no issues are found, say so clearly — and note that 4 independent reviewers agreed.
