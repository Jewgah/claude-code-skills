---
name: review
description: Review code changes for flaws, bugs, security issues, and potential problems
argument-hint: "[scope: staged, unstaged, last-commit, or blank for all]"
---

# Code Review

Perform a thorough code review of the current changes. Act as a senior developer reviewing a pull request.

## Steps

1. **Gather changes based on scope**:
   - If `$ARGUMENTS` contains "staged": only `git diff --cached`
   - If `$ARGUMENTS` contains "unstaged": only `git diff`
   - If `$ARGUMENTS` contains "last-commit": `git rev-parse HEAD~1 >/dev/null 2>&1 && git diff HEAD~1 || git diff $(git hash-object -t tree /dev/null)` (falls back to the empty tree on a repo's first commit)
   - Otherwise: both `git diff` and `git diff --cached` (all pending changes)
   - Also run `git status` for context

2. **Read full files**: For every file that has changes, read the COMPLETE file (not just the diff) to understand the full context around the modifications.

3. **Analyze each change** against this checklist:

### Logic & Correctness
- Are there logic errors, off-by-one mistakes, or wrong conditions?
- Are edge cases handled (null, undefined, empty arrays, missing fields)?
- Do loops and iterations behave correctly?
- Are return values used correctly?

### Security
- Any injection risks (SQL, command, XSS)?
- Is user input validated and sanitized?
- Are there exposed secrets or credentials?
- Are auth checks present where needed?

### Data & State
- Are data operations correct (correct methods, field names, query parameters)?
- Is state managed correctly (component state, query cache)?
- Are race conditions possible?
- Is data transformed correctly between layers?

### Error Handling
- Are async operations properly awaited?
- Are errors caught where they should be?
- Do error paths leave the app in a consistent state?
- Are failures observable - is the error logged with enough context (ids, operation), and do logs avoid leaking secrets/PII?

### Performance
- Any unnecessary re-renders or re-fetches?
- N+1 query problems?
- Large data sets loaded without pagination?
- Missing memoization for expensive computations?

### Project Constraints
- Read CLAUDE.md (if it exists) for project-specific constraints and verify changes don't violate them.

### Breaking Changes
- Could this change break existing functionality?
- Are API contracts preserved?
- Are backwards-incompatible changes flagged?

4. **Produce the review report** in the following format:

## Output Format

For each issue found, report:

**[SEVERITY] Category — File:line**
Description of the issue and why it matters.
Suggested fix (if applicable).

Severity levels:
- **CRITICAL**: Bugs, security holes, data corruption risks — must fix before shipping
- **WARNING**: Potential problems, edge cases, code smells — should fix
- **INFO**: Minor suggestions, style issues, improvements — nice to have

At the end, provide a **Summary** with:
- Total issues by severity
- Overall assessment (safe to ship / needs fixes / needs major rework)
- The single most important thing to address

If no issues are found, say so clearly.

$ARGUMENTS
