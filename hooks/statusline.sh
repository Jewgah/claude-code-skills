#!/usr/bin/env bash
# statusLine: project | branch | N uncommitted | review state | push state | model | effort | plan usage.
# Review state mirrors commit-review-gate's logic, so you SEE the gate before you hit it:
#   reviewed     = /review or /review-deep ran in this repo after the last commit AND the last edit -> commit will pass
#   not reviewed = the gate will block your next commit
# Claude Code pipes the session as JSON on stdin: model, effort, plan usage windows.
# Every window in rate_limits is shown (5h, week, and any other bucket the payload carries),
# so a new bucket appears by itself. Absent fields are skipped: rate_limits only exists for
# subscription plans and only after the first API response of the session.
# read with a timeout, never $(cat): run by hand with stdin closed or never ending, cat would hang forever
input=""; [ -t 0 ] || IFS= read -r -t 2 -d '' input 2>/dev/null
session=""
if [ -n "$input" ] && command -v jq >/dev/null 2>&1; then
  session="$(printf '%s' "$input" | jq -r '
    def word: strings | gsub("[[:cntrl:]]"; " ") | select(. != "");   # one unexpected shape must not drop the rest
    [ (.model | objects | .display_name | word),
      (.effort | objects | .level | word),
      (.rate_limits | objects | to_entries[] | select((.value | type) == "object" and (.value.used_percentage | type) == "number")
        | "\({five_hour:"5h",seven_day:"week"}[.key] // .key) \(.value.used_percentage | round)%") ]
    | join(" | ")' 2>/dev/null)"
  [ -n "$session" ] && session=" | $session"
fi

root="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$root" ]; then echo "no repo${session}"; exit 0; fi

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
elif [ "$branch" != "detached" ] && [ -n "$(git remote 2>/dev/null)" ] \
  && [ "$(git rev-list --count HEAD --not --remotes 2>/dev/null || echo 0)" != "0" ]; then
  push=" | not pushed"   # no upstream: HEAD has commits no remote ref contains (never pushed, or pushed without -u then committed)
fi

echo "${project} | ${branch} | ${dirty} uncommitted${state}${push}${session}"
