#!/usr/bin/env bash
# statusLine: project | branch | N uncommitted | review state | push state.
# Review state mirrors commit-review-gate's logic, so you SEE the gate before you hit it:
#   reviewed     = /review or /review-deep ran in this repo after the last commit AND the last edit -> commit will pass
#   not reviewed = the gate will block your next commit
root="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$root" ]; then echo "no repo"; exit 0; fi

project="$(basename "$root")"
branch="$(git branch --show-current 2>/dev/null)"; : "${branch:=detached}"   # empty, exit 0, on a detached HEAD
dirty="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"

state=""
if [ "$dirty" != "0" ]; then
  thr="$(git log -1 --date=format-local:'%Y-%m-%dT%H:%M:%S' --format=%ad 2>/dev/null)"; : "${thr:=0000}"
  # the gate's rule over EVERY pending file (the gate narrows it to the files being committed), so
  # this may say not reviewed where a commit by explicit path would pass, never the reverse
  edit="$(cd "$root" && { git diff -z --name-only HEAD 2>/dev/null; git ls-files -z -o --exclude-standard; } \
    | python3 -c 'import os,sys,time; now=time.time()+5; m=[t for t in (os.lstat(p).st_mtime for p in sys.stdin.read().split("\0") if p and os.path.lexists(p)) if t <= now]; print(time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(max(m))) if m else "")')"
  [ -n "$edit" ] && [ "$edit" \> "$thr" ] && thr="$edit"
  log="${CLAUDE_SKILL_LOG:-$HOME/.claude/skill-usage.log}"; [ -f "$log" ] || log=/dev/null
  # git gives the physical root, the log records the logical cwd: match either (see the gate).
  prefix="$(git rev-parse --show-prefix 2>/dev/null)"
  rootl="${PWD%/}"; [ -n "$prefix" ] && rootl="${rootl%/${prefix%/}}"
  if awk -F'\t' -v root="$root" -v rootl="$rootl" -v thr="$thr" '
      $2 ~ /^(review|review-deep|code-review|security-review|security-audit)$/ && $3 ~ /^(typed|nl)$/ \
      && ($4 == root  || index($4, root  "/") == 1 \
       || $4 == rootl || index($4, rootl "/") == 1) \
      && $1 >= thr { f=1; exit } END { exit(f?0:1) }' "$log"; then
    state=" | reviewed"
  else
    state=" | not reviewed"
  fi
fi

# ponytail: called "pushed", not "deployed": push != deploy for repos with no CI
# (e.g. a manual rsync deploy), so "deployed" would just be a new untrue label.
push=""
if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
  ahead="$(git rev-list --count '@{u}..HEAD' 2>/dev/null)"
  [ "${ahead:-0}" != "0" ] && push=" | not pushed"
fi

echo "${project} | ${branch} | ${dirty} uncommitted${state}${push}"
