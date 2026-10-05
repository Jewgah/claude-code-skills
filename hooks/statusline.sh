#!/usr/bin/env bash
# statusLine: branch | N dirty | review state.
# The review state mirrors commit-review-gate's logic, so you SEE the gate before you hit it:
#   ok reviewed   = a review ran in this repo after the last commit AND after the last edit -> commit will pass
#   NOT reviewed  = the gate will block your next commit
root="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$root" ]; then echo "no repo"; exit 0; fi

branch="$(git branch --show-current 2>/dev/null || echo 'detached')"
dirty="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"

state=""
if [ "$dirty" != "0" ]; then
  thr="$(git log -1 --date=format-local:'%Y-%m-%dT%H:%M:%S' --format=%ad 2>/dev/null)"; : "${thr:=0000}"
  # same rule as the gate: an edit made after the review needs another one
  edit="$(cd "$root" && { git diff -z --name-only HEAD 2>/dev/null; git ls-files -z -o --exclude-standard; } \
    | python3 -c 'import os,sys,time; now=time.time()+5; m=[t for t in (os.lstat(p).st_mtime for p in sys.stdin.read().split("\0") if p and os.path.lexists(p)) if t <= now]; print(time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(max(m))) if m else "")')"
  [ -n "$edit" ] && [ "$edit" \> "$thr" ] && thr="$edit"
  log="${CLAUDE_SKILL_LOG:-$HOME/.claude/skill-usage.log}"; [ -f "$log" ] || log=/dev/null
  # git gives the physical root, the log records the logical cwd — match either (see the gate).
  prefix="$(git rev-parse --show-prefix 2>/dev/null)"
  rootl="${PWD%/}"; [ -n "$prefix" ] && rootl="${rootl%/${prefix%/}}"
  if awk -F'\t' -v root="$root" -v rootl="$rootl" -v thr="$thr" '
      $2 ~ /^(review|review-deep|code-review|security-review|security-audit)$/ && $3 ~ /^(typed|nl)$/ \
      && ($4 == root  || index($4, root  "/") == 1 \
       || $4 == rootl || index($4, rootl "/") == 1) \
      && $1 >= thr { f=1; exit } END { exit(f?0:1) }' "$log"; then
    state=" | reviewed"
  else
    state=" | UNREVIEWED"
  fi
fi

echo "${branch} | ${dirty} dirty${state}"
