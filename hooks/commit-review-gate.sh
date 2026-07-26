#!/usr/bin/env bash
# commit-review-gate: PreToolUse(Bash). Blocks `git commit` unless a code review
# (review / review-deep / code-review / security-review) ran since the last commit
# in this repo. The model picks the depth; this just enforces that one happened.
# Reuses ~/.claude/skill-usage.log as the "was it reviewed?" signal — no new state.
input="$(cat)"

# Fast path: if the raw payload can't even contain a commit, allow instantly (no jq tax).
case "$input" in *commit*) ;; *) exit 0 ;; esac

# jq is required to read the command safely. Missing jq must FAIL CLOSED — otherwise
# the whole gate silently disappears on a machine without jq.
if ! command -v jq >/dev/null 2>&1; then
  printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"commit-review-gate needs jq and it is not installed (brew install jq). Install it, or remove this hook from ~/.claude/settings.json."}}'
  exit 0
fi

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
# Match `git commit` / `git -C <dir> commit` / `git -c k=v commit`. Note: won't see commits
# buried inside a called script (e.g. `bash deploy.sh`) — those stay ungated.
printf '%s' "$cmd" | grep -Eq 'git( +-[cC] +[^ ]+)* +commit' || exit 0

# One-shot bypass for a trivial commit: `touch ~/.claude/.skip-commit-review`.
if [ -f "$HOME/.claude/.skip-commit-review" ]; then
  rm -f "$HOME/.claude/.skip-commit-review"; exit 0
fi

cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$cwd" ] && cwd="$PWD"
root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
[ -z "$root" ] && exit 0   # not a git repo → nothing to gate

# git reports the PHYSICAL root (/private/var/…) while the log records the cwd as the session
# spells it (/var/…). Under any symlinked path they never match and the gate would deny forever,
# so derive the logical root too — string work only, no extra forks.
prefix="$(git -C "$cwd" rev-parse --show-prefix 2>/dev/null)"   # "" at the root, "sub/" below it
rootl="${cwd%/}"; [ -n "$prefix" ] && rootl="${rootl%/${prefix%/}}"

# Threshold = last commit's local time as an ISO string. Log lines use the same format and
# ISO sorts chronologically, so we string-compare. `--date=format-local` keeps this portable
# (BSD `date -r` and GNU `date -r` mean different things).
thr="$(git -C "$root" log -1 --date=format-local:'%Y-%m-%dT%H:%M:%S' --format=%ad 2>/dev/null)"
: "${thr:=0000}"   # no commits yet → any review counts

log="${CLAUDE_SKILL_LOG:-$HOME/.claude/skill-usage.log}"
[ -f "$log" ] || log=/dev/null
# Reviewed since last commit? Single awk pass: right skill, same repo, ts >= threshold.
if awk -F'\t' -v root="$root" -v rootl="$rootl" -v thr="$thr" '
    $2 ~ /^(review|review-deep|code-review|security-review)$/ \
    && ($4 == root  || index($4, root  "/") == 1 \
     || $4 == rootl || index($4, rootl "/") == 1) \
    && $1 >= thr { found=1; exit } END { exit(found ? 0 : 1) }' "$log"; then
  exit 0
fi

reason="Review-before-commit gate: this repo has changes not yet reviewed since the last commit. Judge the blast radius, then run a review: small / localized / low-risk -> invoke the \"review\" skill; multi-file / shared interface / security / data / migration / deploy-touching -> invoke \"review-deep\". Address the findings, then re-run the commit and it will pass. Trivial change you want to skip: run \`touch ~/.claude/.skip-commit-review\` then commit."
jq -n --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
