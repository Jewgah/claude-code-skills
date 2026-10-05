#!/usr/bin/env bash
# Proves the hooks behave as documented, against a throwaway repo in a temp dir.
# Touches nothing of yours: fake HOME, fake skill log, temp git repo.
#   bash test/run-hooks.sh
K="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
R="$T/repo"; FH="$T/home"; LOG="$T/skill.log"
# HOOKS=~/.claude/hooks runs these assertions against your INSTALLED hooks instead of the kit's.
HOOKS="${HOOKS:-$K/hooks}"
GATE="$HOOKS/commit-review-gate.sh"
# some setups keep the usage logger at ~/.claude/log-skill.sh instead of in hooks/
LOGGER="$HOOKS/log-skill.sh"; [ -f "$LOGGER" ] || LOGGER="$HOME/.claude/log-skill.sh"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1  -> $2"; }

command -v jq >/dev/null || { echo "jq required"; exit 1; }
command -v node >/dev/null || { echo "node required"; exit 1; }

mkdir -p "$R/sub" "$FH/.claude"
cd "$R"
git init -q .; git config user.email t@t.t; git config user.name t
echo v1 > a.txt; git add a.txt; git commit -qm init
echo v2 > a.txt   # an unreviewed change

payload()  { jq -n --arg c "$1" --arg w "${2:-$R}" '{tool_input:{command:$c},cwd:$w}'; }
decision() { local o; o="$(cat)"; [ -z "$o" ] && { echo allow; return; }
             printf '%s' "$o" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null; }
run()      { payload "$1" "$2" | HOME="$FH" CLAUDE_SKILL_LOG="$LOG" bash "$GATE"; }
review_now() { printf '%s\t%s\t%s\t%s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "${1:-review}" typed "${2:-$R}" >> "$LOG"; }

echo "== commit gate =="
: > "$LOG"
d=$(run "git commit -m x" | decision);            [ "$d" = deny ]  && ok "unreviewed commit denied" || bad "unreviewed commit" "$d"
d=$(run "git status" | decision);                 [ "$d" = allow ] && ok "non-commit command allowed" || bad "non-commit" "$d"
d=$(run "git commit-tree abc" | decision);        [ "$d" = deny ]  && ok "git commit-tree also denied (harmless over-reach)" || bad "commit-tree" "$d"
review_now
d=$(run "git commit -m x" | decision);            [ "$d" = allow ] && ok "allowed after a review in this repo" || bad "after review" "$d"
d=$(run "git commit -m x" "$R/sub" | decision);   [ "$d" = allow ] && ok "subdir cwd resolves to the repo root" || bad "subdir cwd" "$d"
: > "$LOG"; review_now review /other/repo
d=$(run "git commit -m x" | decision);            [ "$d" = deny ]  && ok "a review in a DIFFERENT repo does not count" || bad "other repo" "$d"
: > "$LOG"; printf '%s\treview\ttyped\t%s\n' "2020-01-01T00:00:00" "$R" >> "$LOG"
d=$(run "git commit -m x" | decision);            [ "$d" = deny ]  && ok "a review older than the last commit does not count" || bad "stale review" "$d"
: > "$LOG"; review_now; sleep 1; echo v3 > a.txt
d=$(run "git commit -m x" | decision);            [ "$d" = deny ]  && ok "an edit made after the review needs another review" || bad "edit after review" "$d"
sleep 1; echo new > b.txt; review_now; sleep 1; echo newer > b.txt
d=$(run "git commit -m x" | decision);            [ "$d" = deny ]  && ok "an untracked file edited after the review counts too" || bad "untracked edit" "$d"
rm -f b.txt; review_now
d=$(run "git commit -m x" | decision);            [ "$d" = allow ] && ok "a fresh review after the last edit passes" || bad "fresh review" "$d"
: > "$LOG"; printf '%s\treview\tsomething-else\t%s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$R" >> "$LOG"
d=$(run "git commit -m x" | decision);            [ "$d" = deny ]  && ok "a row not written by log-skill.sh does not count" || bad "foreign row" "$d"
echo z > c.txt; touch -t 203001010000 c.txt; : > "$LOG"; review_now
d=$(run "git commit -m x" | decision);            [ "$d" = allow ] && ok "a file dated in the future does not block a reviewed commit" || bad "future mtime" "$d"
rm -f c.txt
# Scoped to the files being committed: another session's newer file must not block a commit by
# explicit path, while anything unclear still checks every pending file.
echo m > mine.txt; touch -t 202601010000 mine.txt a.txt; : > "$LOG"; review_now; sleep 1; echo o > other.txt
d=$(run 'git add mine.txt && git commit -m x' | decision);          [ "$d" = allow ] && ok "another session's newer file does not block a commit by explicit path" || bad "explicit path" "$d"
d=$(run 'git add mine.txt other.txt && git commit -m x' | decision); [ "$d" = deny ]  && ok "a named file edited after the review still blocks" || bad "named newer" "$d"
d=$(run 'git add -A && git commit -m x' | decision);                [ "$d" = deny ]  && ok "git add -A falls back to every pending file" || bad "add -A" "$d"
d=$(run 'git commit -am x' | decision);                             [ "$d" = allow ] && ok "commit -a takes tracked changes, not the newer untracked file" || bad "commit -a" "$d"
git add mine.txt
d=$(run 'sh -c "git add other.txt" && git commit -m x' | decision);  [ "$d" = deny ]  && ok "a staging step the parser cannot see falls back to every pending file" || bad "sh -c staging" "$d"
d=$(run 'git stash pop && git commit -m x' | decision);             [ "$d" = deny ]  && ok "another git subcommand falls back to every pending file" || bad "stash pop" "$d"
git reset -q mine.txt
d=$(run 'git add mine.txt && git commit -m"fix the cat" other.txt' | decision); [ "$d" = deny ]  && ok "an attached -m value does not hide the path after it" || bad "attached -m" "$d"
d=$(run 'git add mine.txt "" other.txt && git commit -m x' | decision);         [ "$d" = deny ]  && ok "an empty argument does not hide the paths after it" || bad "empty arg" "$d"
d=$(run 'git add mine.txt && git commit -m x 2>&1' | decision);                 [ "$d" = allow ] && ok "a 2>&1 redirection keeps the commit scoped" || bad "2>&1" "$d"
sleep 1; echo v4 > a.txt
d=$(run 'git commit -am x' | decision);                             [ "$d" = deny ]  && ok "commit -a sees a tracked file edited after the review" || bad "commit -a tracked" "$d"
rm -f mine.txt other.txt
: > "$LOG"
d=$(run "git -C /tmp/x commit -m x" | decision);  [ "$d" = deny ]  && ok "git -C <dir> commit matched" || bad "git -C" "$d"
d=$(run "git -c user.name=z commit -m x" | decision); [ "$d" = deny ] && ok "git -c k=v commit matched" || bad "git -c" "$d"
d=$(run "git commit --no-verify -m x" | decision);[ "$d" = deny ]  && ok "--no-verify is still gated" || bad "--no-verify" "$d"
d=$(run "git commit -m x" /tmp | decision);       [ "$d" = allow ] && ok "outside a repo: nothing to gate" || bad "non-repo" "$d"
# The bypass marker is PER REPO: ~/.claude/.skip-commit-review-<repo name>-<cksum of the root>.
marker_for() { local r; r="$(git -C "$1" rev-parse --show-toplevel)"
  echo "$FH/.claude/.skip-commit-review-$(basename "$r" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g')-$(printf '%s' "$r" | cksum | cut -d' ' -f1)"; }
MR="$(marker_for "$R")"
r=$(run "git commit -m x" | jq -r '.hookSpecificOutput.permissionDecisionReason')
case "$r" in *"touch $MR"*) ok "deny message prints this repo's marker path";; *) bad "deny message marker" "$r";; esac
touch "$FH/.claude/.skip-commit-review"
d=$(run "git commit -m x" | decision);            [ "$d" = deny ]  && ok "the old global marker no longer unlocks anything" || bad "old global marker" "$d"
touch "$MR"
d=$(run "git commit -m x" | decision);            [ "$d" = allow ] && ok "this repo's marker allows" || bad "bypass" "$d"
[ -f "$MR" ] && bad "bypass consumed" "marker still there" || ok "bypass marker is one-shot"

# The repo committed to is not always .cwd. Resolving from .cwd alone mis-gated BOTH
# directions; the dangerous half PASSED an unreviewed commit whenever the session sat
# in some other, recently reviewed repo.
echo "== commit gate: target repo resolution =="
R2="$T/repo2"; mkdir -p "$R2"
git init -q "$R2"; git -C "$R2" config user.email t@t.t; git -C "$R2" config user.name t
echo v1 > "$R2/a.txt"; git -C "$R2" add a.txt; git -C "$R2" commit -qm init
echo v2 > "$R2/a.txt"   # an unreviewed change in repo2
: > "$LOG"; review_now review "$R"      # ONLY repo1 has been reviewed
d=$(run "cd $R2 && git commit -m x" | decision);  [ "$d" = deny ]  && ok "cd <other repo> + commit is gated on THAT repo" || bad "cd target" "$d"
d=$(run "git -C $R2 commit -m x" | decision);     [ "$d" = deny ]  && ok "git -C <other repo> is gated on THAT repo" || bad "-C target" "$d"
d=$(run "cd $R && git commit -m x" "$R2" | decision); [ "$d" = allow ] && ok "reviewed repo reached via cd is allowed" || bad "cd to reviewed" "$d"
d=$(run "git commit -m 'use git -C $R2 here'" | decision); [ "$d" = allow ] && ok "-C inside the message is not a target" || bad "-C in message" "$d"
d=$(run "cd /nope/zzz && git commit -m x" | decision); [ "$d" = allow ] && ok "unresolvable target degrades to cwd" || bad "bad target" "$d"
d=$(run "(cd $R2 && git commit -m x)" | decision); [ "$d" = deny ] && ok "(cd <other repo> && commit) in a subshell is gated on THAT repo" || bad "subshell cd target" "$d"
d=$(run "{ cd $R2; git commit -m x; }" | decision); [ "$d" = deny ] && ok "{ cd <other repo>; commit; } group is gated on THAT repo" || bad "group cd target" "$d"
d=$(run "sh -c \"cd $R2 && git commit -m x\"" | decision); [ "$d" = deny ] && ok "sh -c \"cd <other repo> && commit\" is gated on THAT repo" || bad "sh -c cd target" "$d"
M2="$(marker_for "$R2")"; MR="$(marker_for "$R")"; touch "$MR"
d=$(run "git -C $R2 commit -m x" | decision);     [ "$d" = deny ]  && ok "another repo's marker does not unlock this one" || bad "cross-repo marker" "$d"
[ -f "$MR" ] && ok "another repo's marker is left untouched" || bad "cross-repo marker consumed" "gone"
rm -f "$MR"; touch "$M2"
d=$(run "git -C $R2 commit -m x" | decision);     [ "$d" = allow ] && ok "git -C <repo> uses THAT repo's marker" || bad "-C marker" "$d"
# A repo path containing a SPACE must still be seen as a commit at all. Matching the -C
# argument as [^ ]+ missed it entirely, leaving such commits completely ungated.
SP="$T/my repo"; mkdir -p "$SP"
git init -q "$SP"; git -C "$SP" config user.email t@t.t; git -C "$SP" config user.name t
echo v1 > "$SP/a.txt"; git -C "$SP" add a.txt; git -C "$SP" commit -qm init
echo v2 > "$SP/a.txt"
d=$(run "git -C \"$SP\" commit -m x" | decision);  [ "$d" = deny ] && ok "quoted -C path with a space is still gated" || bad "-C spaced path" "$d"
d=$(run "cd \"$SP\" && git commit -m x" | decision); [ "$d" = deny ] && ok "quoted cd path with a space is still gated" || bad "cd spaced path" "$d"
: > "$LOG"; review_now security-audit "$R"
d=$(run "git commit -m x" | decision);            [ "$d" = allow ] && ok "security-audit satisfies the gate" || bad "security-audit" "$d"
s=$(cd "$R" && CLAUDE_SKILL_LOG="$LOG" bash "$HOOKS/statusline.sh")
case "$s" in *"| reviewed"*) ok "statusline agrees security-audit counts";; *) bad "statusline security-audit" "$s";; esac

echo "== plan gate =="
d=$(jq -n '{tool_input:{plan:"1. do the thing"}}' | node "$HOOKS/plan-review-gate.mjs" | decision)
[ "$d" = deny ] && ok "unreviewed plan denied" || bad "unreviewed plan" "$d"
out=$(jq -n '{tool_input:{plan:"1. do it\n<!-- plan-reviewed -->"}}' | node "$HOOKS/plan-review-gate.mjs")
[ -z "$out" ] && ok "plan carrying the marker is allowed" || bad "marked plan" "$out"
d=$(printf 'not json' | node "$HOOKS/plan-review-gate.mjs" | decision)
[ "$d" = deny ] && ok "malformed payload fails closed" || bad "malformed payload" "$d"

echo "== statusline =="
: > "$LOG"
s=$(cd "$R" && CLAUDE_SKILL_LOG="$LOG" bash "$HOOKS/statusline.sh")
case "$s" in *UNREVIEWED*) ok "shows UNREVIEWED: $s";; *) bad "statusline unreviewed" "$s";; esac
review_now review-deep
s=$(cd "$R" && CLAUDE_SKILL_LOG="$LOG" bash "$HOOKS/statusline.sh")
case "$s" in *"| reviewed"*) ok "shows reviewed: $s";; *) bad "statusline reviewed" "$s";; esac
s=$(cd /tmp && bash "$HOOKS/statusline.sh"); [ "$s" = "no repo" ] && ok "outside a repo: $s" || bad "statusline no-repo" "$s"

echo "== usage logger =="
rm -f "$FH/.claude/skill-usage.log"
jq -n --arg w "$R" '{prompt:"/review-deep staged",cwd:$w}' | HOME="$FH" bash "$LOGGER" prompt
line=$(tail -1 "$FH/.claude/skill-usage.log" 2>/dev/null)
case "$line" in *$'\t'review-deep$'\t'typed*) ok "typed /command logged";; *) bad "logger typed" "$line";; esac
jq -n --arg w "$R" '{prompt:"/Users/someone/file.md is the path",cwd:$w}' | HOME="$FH" bash "$LOGGER" prompt
n=$(wc -l < "$FH/.claude/skill-usage.log" | tr -d ' ')
[ "$n" = 1 ] && ok "a pasted path is not logged as a command" || bad "path false-positive" "$n lines"
jq -n --arg w "$R" '{tool_input:{skill:"review"},cwd:$w}' | HOME="$FH" bash "$LOGGER" tool
case "$(tail -1 "$FH/.claude/skill-usage.log")" in *$'\t'review$'\t'nl*) ok "natural-language skill use logged";; *) bad "logger nl" "";; esac

echo; echo "RESULT: $pass passed, $fail failed"
exit $((fail > 0))
