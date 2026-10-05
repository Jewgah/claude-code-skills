#!/usr/bin/env bash
# commit-review-gate: PreToolUse(Bash). Blocks `git commit` unless a code review
# (review / review-deep / code-review / security-review / security-audit) ran since the last commit
# in this repo. The model picks the depth; this just enforces that one happened.
# Reuses ~/.claude/skill-usage.log as the "was it reviewed?" signal - no new state.
input="$(cat)"

# Fast path: if the raw payload can't even contain a commit, allow instantly (no jq tax).
case "$input" in *commit*) ;; *) exit 0 ;; esac

# jq is required to read the command safely. Missing jq must FAIL CLOSED, otherwise
# the whole gate silently disappears on a machine without jq.
if ! command -v jq >/dev/null 2>&1; then
  printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"commit-review-gate needs jq and it is not installed (brew install jq). Install it, or remove this hook from ~/.claude/settings.json."}}'
  exit 0
fi

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
# Match `git commit` / `git -C <dir> commit` / `git -c k=v commit`. The arg may be QUOTED and
# contain spaces (`git -C "~/My Projects/app" commit`); matching only [^ ]+ there missed the
# commit entirely and left it completely ungated. Note: won't see commits buried inside a
# called script (e.g. `bash deploy.sh`) - those stay ungated.
printf '%s' "$cmd" | grep -Eq 'git( +-[cC] +("[^"]*"|'\''[^'\'']*'\''|[^ ]+))* +commit' || exit 0

cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$cwd" ] && cwd="$PWD"

# The repo being committed to is NOT always .cwd. `cd <repo> && git commit` and
# `git -C <repo> commit` both target another one, and resolving from .cwd alone
# mis-gated BOTH directions: it denied a genuinely reviewed commit, and (the
# dangerous half) it PASSED an unreviewed commit whenever the session happened to
# sit in some other, recently reviewed repo. So read the target out of the command
# first, and fall back to .cwd.
target=""
# 1. `git [-c k=v]... -C <dir> ... commit`. Scan ONLY between `git` and `commit`,
#    so a -C inside a commit message can never be mistaken for the flag.
gitseg="${cmd#*git }"; gitseg="${gitseg%%commit*}"
case "$gitseg" in
  *-C*) target="$(printf '%s' "$gitseg" | sed -nE 's/.*-C[[:space:]]+("[^"]*"|'\''[^'\'']*'\''|[^[:space:]]+).*/\1/p')" ;;
esac
# 2. else a `cd <path>` running BEFORE the git call. Prefix only, for the same
#    reason: a `cd` inside a -m message must not be read as a directory change.
if [ -z "$target" ]; then
  pre="${cmd%%git *}"
  # `cd` may follow a separator, a subshell `(`, a group `{` or the quote of `sh -c "cd ..."`
  [ "$pre" != "$cmd" ] && target="$(printf '%s' "$pre" | sed -nE 's/.*(^|[;&|({"][[:space:]]*)cd[[:space:]]+("[^"]*"|'\''[^'\'']*'\''|[^[:space:]&;|]+).*/\2/p')"
fi
# strip one layer of quotes, expand a leading ~, resolve relative against .cwd
target="${target%\"}"; target="${target#\"}"; target="${target%\'}"; target="${target#\'}"
case "$target" in "~"|"~/"*) target="$HOME${target#\~}" ;; esac
case "$target" in ""|/*) ;; *) target="$cwd/$target" ;; esac
# Trust it ONLY if it really is a repo. A misparse must degrade to .cwd behaviour,
# never invent a pass for a repo nobody reviewed.
if [ -n "$target" ] && git -C "$target" rev-parse --show-toplevel >/dev/null 2>&1; then
  cwd="$target"
fi

root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
[ -z "$root" ] && exit 0   # not a git repo: nothing to gate

# One-shot bypass for a trivial commit, PER REPO. It used to be a single global file, so any
# commit in any repo, from any session, consumed a marker created for another repo.
slug="$(basename "$root" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g')"
crc="$(printf '%s' "$root" | cksum | cut -d' ' -f1)"
marker="$HOME/.claude/.skip-commit-review-$slug-$crc"
if [ -f "$marker" ]; then rm -f "$marker"; exit 0; fi

# git reports the PHYSICAL root (/private/var/…) while the log records the cwd as the session
# spells it (/var/…). Under any symlinked path they never match and the gate would deny forever,
# so derive the logical root too: string work only, no extra forks.
prefix="$(git -C "$cwd" rev-parse --show-prefix 2>/dev/null)"   # "" at the root, "sub/" below it
rootl="${cwd%/}"; [ -n "$prefix" ] && rootl="${rootl%/${prefix%/}}"

# Threshold = last commit's local time as an ISO string. Log lines use the same format and
# ISO sorts chronologically, so we string-compare. `--date=format-local` keeps this portable
# (BSD `date -r` and GNU `date -r` mean different things).
thr="$(git -C "$root" log -1 --date=format-local:'%Y-%m-%dT%H:%M:%S' --format=%ad 2>/dev/null)"
: "${thr:=0000}"   # no commits yet: any review counts
# A review only covers what existed when it ran: an edit made after it (a review fix, a late
# tweak) needs another one. So the review must also be newer than the newest pending file.
# ponytail: mtime, not content; a deletion after the review is not seen. Content receipt if that bites.
edit="$(cd "$root" && { git diff -z --name-only HEAD 2>/dev/null; git ls-files -z -o --exclude-standard; } \
  | python3 -c 'import os,sys,time; m=[os.lstat(p).st_mtime for p in sys.stdin.read().split("\0") if p and os.path.lexists(p)]; print(time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(max(m))) if m else "")')"
[ -n "$edit" ] && [ "$edit" \> "$thr" ] && thr="$edit"

log="${CLAUDE_SKILL_LOG:-$HOME/.claude/skill-usage.log}"
[ -f "$log" ] || log=/dev/null
# Reviewed since last commit? Single awk pass: right skill, same repo, ts >= threshold.
if awk -F'\t' -v root="$root" -v rootl="$rootl" -v thr="$thr" '
    $2 ~ /^(review|review-deep|code-review|security-review|security-audit)$/ && $3 ~ /^(typed|nl)$/ \
    && ($4 == root  || index($4, root  "/") == 1 \
     || $4 == rootl || index($4, rootl "/") == 1) \
    && $1 >= thr { found=1; exit } END { exit(found ? 0 : 1) }' "$log"; then
  exit 0
fi

reason="Review-before-commit gate: this repo has changes not yet reviewed (no review since the last commit, or files were edited after it). Judge the blast radius, then run a review: small / localized / low-risk -> invoke the \"review\" skill; multi-file / shared interface / security / data / migration / deploy-touching -> invoke \"review-deep\". Address the findings, then re-run the commit and it will pass. Trivial change you want to skip: run \`touch $marker\` as its own step, then commit (the marker is for this repo only). Note: the review counts only if it was logged from a session whose working directory is inside this repo; a subagent inherits its parent session's."
jq -n --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
