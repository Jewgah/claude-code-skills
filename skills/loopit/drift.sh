#!/usr/bin/env bash
# drift.sh <repo> <baseline-sha>
#
# Lists the lines of docs and memory that still mention a name this change REMOVED or RENAMED:
# files deleted or renamed away, and identifiers defined on removed lines that no added line
# defines or mentions again. Information for the builder, never a gate.
# Searches: the repo's tracked *.md, the project's memory folder, the home memory folder.
# Blind spot, by design: a changed VALUE (hourly -> every 30 min) is not a removed name.
# Exit 0 always, 4 on bad input. Written for macOS /bin/bash 3.2 and BSD sed/grep.

set -f   # tokens come from file names and code: never let one glob
repo=$1; base=$2
root=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null) || { echo "DRIFT invalid: not a git repo: $repo"; exit 4; }
git -C "$root" cat-file -e "$base^{commit}" 2>/dev/null || { echo "DRIFT invalid: unknown baseline: $base"; exit 4; }

stop=" index readme utils config helpers types constants setup tests "
diff=$(git -C "$root" diff -U0 -M "$base")
# added = "+" lines, new paths of renames, untracked file paths, and untracked text files under 1 MB:
# at gate time the builder's new files are not committed yet, and a name moved into one (or a file
# moved to a new path) must not read as removed
added=$(printf '%s\n' "$diff" | grep '^+' | grep -v '^+++'
  git -C "$root" diff --name-status -M "$base" | awk -F'\t' '$1 ~ /^R/{print $3}'
  git -C "$root" ls-files --others --exclude-standard
  git -C "$root" ls-files -z --others --exclude-standard | (cd "$root" &&
    xargs -0 -r sh -c 'find "$@" -type f -size -1024k -print0' _ | xargs -0 -r grep -Ih '' 2>/dev/null))   # text under 1 MB: never a dump
# identifiers come from removed CODE lines only: a doc sentence like "the class RetryManager" is prose
removed=$(git -C "$root" diff -U0 -M "$base" -- . ':(exclude)*.md' ':(exclude)*.txt' ':(exclude)*.rst' | grep '^-' | grep -v '^---')

cands=$(
  # files deleted, or renamed away (old side of the rename)
  git -C "$root" diff --name-status -M "$base" | awk -F'\t' '$1=="D"{print $2} $1 ~ /^R/{print $2}' |
    while IFS= read -r p; do b=${p##*/}; echo "${b%.*}"; done
  # identifiers defined on removed lines, and env-style names
  printf '%s\n' "$removed" | sed -nE 's/.*(^|[^A-Za-z0-9_])(function|func|fn|def|class|const|let|var|interface|type|enum)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\3/p'
  printf '%s\n' "$removed" | grep -oE '[A-Z][A-Z0-9]*_[A-Z0-9_]+'
)

tokens=""; n=0
for t in $(printf '%s\n' "$cands" | sort -u); do
  [ ${#t} -lt 6 ] && continue
  case "$stop" in *" $(printf '%s' "$t" | tr 'A-Z' 'a-z') "*) continue ;; esac
  printf '%s\n' "$added" | grep -qwF -- "$t" && continue   # still there: not removed
  tokens="$tokens $t"; n=$((n + 1)); [ "$n" -ge 50 ] && break   # ponytail: 50 names cap a huge diff
done
[ -z "$tokens" ] && { echo "DRIFT: none (no removed or renamed names)"; exit 0; }

slug=$(printf '%s' "$root" | sed 's/[^A-Za-z0-9]/-/g')
mem="$HOME/.claude/projects/$slug/memory"
home_mem="$HOME/.claude/projects/$(printf '%s' "$HOME" | sed 's/[^A-Za-z0-9]/-/g')/memory"
hits=$(
  for t in $tokens; do
    git -C "$root" ls-files -z '*.md' | (cd "$root" && xargs -0 -r grep -HnwF -- "$t" 2>/dev/null) | sed "s/\$/  [$t]/"
    for d in "$mem" "$home_mem"; do
      [ -d "$d" ] && grep -rHnwF --include='*.md' -- "$t" "$d" 2>/dev/null | sed "s#^$HOME#~#; s/\$/  [$t]/"
    done
  done | sort -u
)
[ -z "$hits" ] && { echo "DRIFT: none (removed names:$tokens; no doc or memory mentions them)"; exit 0; }
total=$(printf '%s\n' "$hits" | wc -l | tr -d ' ')
printf '%s\n' "$hits" | head -20
[ "$total" -gt 20 ] && echo "... $((total - 20)) more"
echo "DRIFT: $total hits"
exit 0
