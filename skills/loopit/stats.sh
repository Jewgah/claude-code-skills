#!/usr/bin/env bash
# stats.sh add <date> <repo> <task> <builder_model> <checks> <red> <gate_rounds> <first_pass> <disputes> <status>
# stats.sh                  -> last 30 days: first-pass rate on tasks that had executable checks
# One tab-separated line per loopit task in ~/.claude/loopit-stats.tsv (override: LOOPIT_STATS).
# Local file, never committed. Values are single tokens: a malformed row is refused, not written.

f=${LOOPIT_STATS:-$HOME/.claude/loopit-stats.tsv}

if [ "$1" = add ]; then
  shift
  [ $# -eq 10 ] || { echo "stats: add needs 10 values, got $#" >&2; exit 4; }
  for v in "$@"; do
    case "$v" in ""|*[[:space:]]*) echo "stats: empty value or whitespace in '$v'" >&2; exit 4 ;; esac
  done
  case "$5$7$9" in *[!0-9]*) echo "stats: checks, gate_rounds and disputes must be whole numbers" >&2; exit 4 ;; esac
  [ -f "$f" ] || printf 'date\trepo\ttask\tbuilder_model\tchecks\tred\tgate_rounds\tfirst_pass\tdisputes\tstatus\n' > "$f"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >> "$f"
  exit 0
fi

[ -f "$f" ] || { echo "no loopit stats yet ($f)"; exit 0; }
# perl, not date -v (BSD) or date -d (GNU): one spelling on macOS and Linux
since=$(perl -MPOSIX -e 'print strftime("%Y-%m-%d", localtime(time - 30 * 86400))')
awk -F'\t' -v since="$since" '
  NR > 1 && $1 >= since { t++; if ($5 > 0) { c++; rc[$2]++; if ($8 == "yes") { y++; ry[$2]++ } } }
  END {
    printf "last 30 days: %d tasks, %d with executable checks, first-pass %d/%d (%d%%)\n", t, c, y, c, c ? 100 * y / c : 0
    for (r in rc) printf "  %s: first-pass %d/%d\n", r, ry[r], rc[r]
  }' "$f"
