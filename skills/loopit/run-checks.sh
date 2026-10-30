#!/usr/bin/env bash
# run-checks.sh <checks.json> red <repo|->
# run-checks.sh <checks.json> green <repo|-> <hash>
# run-checks.sh <checks.json> committed <repo> <sha> <hash>
#
# The /loopit gate. The verdict is exit codes, never a model's opinion.
#   red       : install the check files, run every check, uninstall. Each check must FAIL, and its log
#               must contain its "red" substring (fails for the right reason, not an import error).
#               On red-ok prints HASH <h> of every file in the manifest folder except logs: the
#               orchestrator keeps it, the builder never sees it.
#   green     : tampered unless the folder still matches <hash> (checked first, even with 0 checks).
#               Then install, run. All pass -> files LEFT in place for the commit. No <hash> (an
#               orchestrator on the pre-hash protocol): runs with a NO-HASH warning.
#   committed : folder still matches <hash>, and every check file committed at <sha> is identical.
# Repo "-" = no-repo mode: nothing is installed, commands run from the manifest's own folder.
#
# stdout: one line per check, then a RESULT line. Never the logs (<manifest dir>/<mode>-<i>.log).
# Exit: 0 ok | 1 not ok (red-bad, green-fail, committed-diff) | 2 tampered | 3 collision | 4 bad input.
# At most 3 checks, 180 s each: always under the Bash tool's 600 s ceiling.
# Written for macOS /bin/bash 3.2: no associative arrays, no mapfile, no set -u.

manifest=$1; mode=$2; repo=$3; extra=$4; given_hash=$5
die() { echo "RESULT invalid: $*"; exit 4; }
[ -f "$manifest" ] || die "manifest not found: $manifest"
case "$mode" in red|green|committed) ;; *) die "mode must be red, green or committed" ;; esac
[ -n "$repo" ] || die "repo missing (a path, or - for no-repo)"
command -v jq >/dev/null || die "jq not installed"
jq -e '.checks | type == "array"' "$manifest" >/dev/null 2>&1 || die "manifest has no checks array"

dir=$(cd "$(dirname "$manifest")" && pwd)
if [ "$repo" = - ]; then
  [ "$mode" = committed ] && die "committed mode needs a repo"
  workdir=$dir
else
  [ -d "$repo" ] || die "repo not found: $repo"
  repo=$(cd "$repo" && pwd); workdir=$repo
fi

# every file of the check folder except run logs: manifest, runner tests and scripts called by path
check_files() { find "$dir" -type f ! -name '*.log' | LC_ALL=C sort; }
sha=shasum; command -v shasum >/dev/null || sha=sha1sum   # same output format; Alpine ships only sha1sum
hash_now() { check_files | while IFS= read -r f; do printf '%s\n' "${f#"$dir"/}"; cat "$f"; done | $sha | cut -d' ' -f1; }
tamper_gate() { # <expected hash>
  [ "$(hash_now)" = "$1" ] && return 0
  echo "TAMPERED a file in the check folder changed since the red run"; echo "RESULT tampered"; exit 2
}

if [ "$mode" = committed ]; then
  [ -n "$extra" ] && [ -n "$given_hash" ] || die "committed mode needs a sha and the HASH"
  tamper_gate "$given_hash"
  diffs=0
  while IFS=$'\t' read -r src dest; do
    [ -z "$src" ] && continue
    if git -C "$repo" show "$extra:$dest" 2>/dev/null | cmp -s - "$dir/$src"; then echo "SAME $dest"
    else echo "COMMITTED-DIFF $dest (differs from the check that passed, or is missing at $extra)"; diffs=1; fi
  done < <(jq -r '.files[]? | "\(.src)\t\(.dest)"' "$manifest")
  [ "$diffs" -eq 0 ] && { echo "RESULT committed-ok"; exit 0; }
  echo "RESULT committed-diff"; exit 1
fi

n=$(jq '.checks | length' "$manifest")
[ "$n" -le 3 ] || die "$n checks: at most 3"
# local only: no Bash hook sees inside a check, so scan the manifest and every file it may call for a
# remote shell in command position (line start, after ; & | ( or a quote)
if check_files | tr '\n' '\0' | xargs -0 grep -lE "(^|[;&|(\"'][[:space:]]*)(ssh|scp|sftp)[[:space:]]" 2>/dev/null | grep -q .; then
  die "a check calls ssh, scp or sftp: checks are local only"
fi

[ "$mode" = green ] && [ -n "$extra" ] && tamper_gate "$extra"   # before the 0-check exit: emptying the list is tampering too
if [ "$n" -eq 0 ]; then echo "RESULT none: $(jq -r '.none // "no reason given"' "$manifest")"; exit 0; fi
[ "$mode" = green ] && [ -z "$extra" ] && echo "NO-HASH tamper check skipped: pass the HASH from the red run"

installed=()
uninstall() {
  for f in "${installed[@]}"; do
    rm -f "$f"
    # remove the empty folders left behind, never the repo itself
    d=$(dirname "$f")
    while [ "$d" != "$repo" ] && [ "${d#"$repo"/}" != "$d" ] && rmdir "$d" 2>/dev/null; do d=$(dirname "$d"); done
  done
  installed=()
}
trap 'uninstall; echo "RESULT interrupted"; exit 1' INT TERM

if [ "$repo" != - ]; then
  while IFS=$'\t' read -r src dest; do
    [ -z "$src" ] && continue
    case "$dest" in ""|/*|*..*) uninstall; die "dest must be a relative path inside the repo: '$dest'" ;; esac
    case "/$dest/" in */.git/*) uninstall; die "dest must be outside .git: '$dest'" ;; esac
    [ -f "$dir/$src" ] || { uninstall; die "check file not found: $dir/$src"; }
    if [ -e "$repo/$dest" ]; then
      uninstall; echo "COLLISION $dest already exists in the repo, nothing overwritten"; echo "RESULT collision"; exit 3
    fi
    # -p keeps the check-writer's mtime, which predates the builder's review: installing the checks
    # must not read as "a file edited after the review" to commit-review-gate.
    mkdir -p "$(dirname "$repo/$dest")" && cp -p "$dir/$src" "$repo/$dest" || { uninstall; die "install failed: $dest"; }
    installed+=("$repo/$dest")
  done < <(jq -r '.files[]? | "\(.src)\t\(.dest)"' "$manifest")
fi

bad=0
for ((i = 0; i < n; i++)); do
  name=$(jq -r ".checks[$i].name // \"check $i\"" "$manifest")
  cmd=$(jq -r ".checks[$i].cmd // empty" "$manifest")
  red=$(jq -r ".checks[$i].red // empty" "$manifest")
  log="$dir/$mode-$i.log"
  if [ -z "$cmd" ]; then echo "INVALID $name (no cmd)"; bad=1; continue; fi
  # ponytail: alarm kills the shell, not its children; a hung runner can outlive the 180 s.
  (cd "$workdir" && perl -e 'alarm shift; exec @ARGV' 180 bash -c "$cmd") >"$log" 2>&1
  rc=$?
  [ "$rc" -eq 142 ] && echo "TIMEOUT $name (180 s)"
  if [ "$mode" = red ]; then
    if [ "$rc" -eq 0 ]; then echo "PASSES-AT-BASELINE $name"; bad=1
    elif [ -z "$red" ]; then echo "NO-RED-SUBSTRING $name (exit $rc)"; bad=1
    elif grep -qF -- "$red" "$log"; then echo "RED-OK $name"
    else echo "RED-WRONG-REASON $name (exit $rc, log lacks: $red)"; bad=1; fi
  else
    if [ "$rc" -eq 0 ]; then echo "PASS $name"; else echo "FAIL $name (exit $rc)"; bad=1; fi
  fi
done

if [ "$mode" = red ]; then
  uninstall
  [ "$bad" -eq 0 ] && { echo "HASH $(hash_now)"; echo "RESULT red-ok"; exit 0; }
  echo "RESULT red-bad"; exit 1
fi
if [ "$bad" -eq 0 ]; then
  for f in "${installed[@]}"; do echo "INSTALLED ${f#"$repo"/}"; done
  echo "RESULT green-ok"; exit 0
fi
uninstall; echo "RESULT green-fail"; exit 1
