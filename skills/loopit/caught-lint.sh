#!/usr/bin/env bash
# caught-lint.sh <repo> <sha>   (the task's CAUGHT: entries on stdin)
# Every mistake a task caught must leave a check behind, or say why none is possible.
# Stdin is either the single line "none caught", or one entry per line (a leading "- " is fine):
#   <the mistake, one line> -> check: <repo path added or changed in <sha>>
#   <the mistake, one line> -> none: <why no mechanical check is possible, 3 words or more>
# The split is at the LAST " -> ", so the mistake may contain one; the path or reason may not.
# A check must also have been seen RED against the pre-fix code (copy, revert the fix, run, restore
# from the copy). No script can prove that part: it is on trust, like MUTATION-PROOFS.
# Output: BAD lines (exit 1), NONE lines for the End report, then "CAUGHT n, check c, none k".
# Exit: 0 ok, 1 a bad entry, 4 usage.

repo=$1; sha=$2
[ -n "$repo" ] && [ -n "$sha" ] || { echo "usage: caught-lint.sh <repo> <sha> < caught.txt" >&2; exit 4; }
changed=$(git -c core.quotePath=false -C "$repo" diff-tree --root -m --no-commit-id --name-only -r "$sha" 2>/dev/null) \
  || { echo "caught-lint: cannot read commit $sha in $repo" >&2; exit 4; }

input=$(cat)
trimmed=$(printf '%s' "$input" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')
[ "$trimmed" = "none caught" ] && { echo "CAUGHT 0, check 0, none 0"; exit 0; }
[ -n "$trimmed" ] || { echo "BAD empty CAUGHT: write \"none caught\" or one entry per line"; exit 1; }

n=0; c=0; k=0; bad=0
while IFS= read -r line || [ -n "$line" ]; do
  line=$(printf '%s' "$line" | sed 's/^[[:space:]]*-[[:space:]]*//; s/^[[:space:]]*//; s/[[:space:]]*$//')
  [ -z "$line" ] && continue
  n=$((n + 1))
  mistake=${line% -> *}   # split at the LAST arrow: a mistake may itself contain one
  if [ "$mistake" = "$line" ] || [ -z "$mistake" ]; then
    echo "BAD $line: needs '<mistake> -> check: <path>' or '<mistake> -> none: <reason>'"; bad=1; continue
  fi
  rest=${line##* -> }
  case "$rest" in
    check:*)
      path=$(printf '%s' "${rest#check:}" | sed 's/^[[:space:]]*//; s/`//g; s#^\./##')
      if [ -n "$path" ] && printf '%s\n' "$changed" | grep -qxF -- "$path"; then c=$((c + 1))
      else echo "BAD $line: '$path' is not a file changed in $sha"; bad=1; fi ;;
    none:*)
      reason=$(printf '%s' "${rest#none:}" | sed 's/^[[:space:]]*//')
      # ponytail: a word count only stops "none: hard"; the user reads every NONE line at the End report
      if [ "$(printf '%s' "$reason" | wc -w | tr -d ' ')" -ge 3 ]; then k=$((k + 1)); echo "NONE $line"
      else echo "BAD $line: a none: reason needs 3 words or more"; bad=1; fi ;;
    *) echo "BAD $line: after '->' write 'check:' or 'none:'"; bad=1 ;;
  esac
done <<< "$input"

echo "CAUGHT $n, check $c, none $k"
exit $bad
