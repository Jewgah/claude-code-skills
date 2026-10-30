#!/usr/bin/env bash
# Self-check for the loopit gate scripts. Run: bash test-scripts.sh   (exit 0 = all green)
# RUN_CHECKS=/path/to/copy overrides the script under test, which is how a mutation is proven red.

here=$(cd "$(dirname "$0")" && pwd)
RC=${RUN_CHECKS:-$here/run-checks.sh}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fails=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
expect() { # name expected_exit actual_exit
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (exit $3, expected $2)"; fi
}

repo=$tmp/repo; checks=$tmp/checks
mkdir -p "$repo" "$checks"
git -C "$repo" init -q && echo x > "$repo/existing.txt" && git -C "$repo" add . \
  && git -C "$repo" -c user.name=t -c user.email=t@t commit -qm init
echo "check body" > "$checks/t.txt"
clean() { [ -z "$(git -C "$repo" status --porcelain)" ]; }

manifest() { # cmd red [dest]
  jq -n --arg cmd "$1" --arg red "$2" --arg dest "${3:-tests/t.txt}" \
    '{task:"T1", checks:[{name:"c1", intent:"i", cmd:$cmd, red:$red}], files:[{src:"t.txt", dest:$dest}], none:null}' \
    > "$checks/checks.json"
}
sha=shasum; command -v shasum >/dev/null || sha=sha1sum
hashof() { find "$checks" -type f ! -name '*.log' | LC_ALL=C sort | while IFS= read -r f; do printf '%s\n' "${f#"$checks"/}"; cat "$f"; done | $sha | cut -d' ' -f1; }   # same formula as the script

# --- red mode
manifest 'test -f tests/t.txt && echo boom; exit 1' boom
out=$(bash "$RC" "$checks/checks.json" red "$repo"); expect "red: fails for the right reason, file visible during run" 0 $?
echo "$out" | grep -q 'RESULT red-ok' || bad "red: RESULT red-ok line"
echo "$out" | grep -q "^HASH $(hashof)$" && ok "red-ok: prints the HASH of manifest + files" || bad "red-ok: prints the HASH of manifest + files"
clean && ok "red: repo tree clean afterwards" || bad "red: repo tree clean afterwards"
[ ! -d "$repo/tests" ] && ok "red: created folder removed" || bad "red: created folder removed"

manifest 'exit 1' boom
bash "$RC" "$checks/checks.json" red "$repo" >/dev/null; expect "red: failing for the wrong reason is red-bad" 1 $?
manifest 'echo boom' boom
bash "$RC" "$checks/checks.json" red "$repo" >/dev/null; expect "red: passing at baseline is red-bad, even with the substring" 1 $?
manifest 'echo boom; exit 1' ''
bash "$RC" "$checks/checks.json" red "$repo" >/dev/null; expect "red: empty red substring is red-bad" 1 $?
manifest 'ssh example.invalid true; exit 1' boom
bash "$RC" "$checks/checks.json" red "$repo" >/dev/null; expect "remote command in a check refused" 4 $?
clean && ok "remote command: nothing installed" || bad "remote command: nothing installed"
printf 'echo start\nssh example.invalid true\nexit 1\n' > "$checks/probe.sh"
manifest "bash $checks/probe.sh; echo boom; exit 1" boom
bash "$RC" "$checks/checks.json" red "$repo" >/dev/null; expect "remote command inside a script the check calls refused" 4 $?
rm -f "$checks/probe.sh"
jq '.checks[0].name = "rejects ssh keys"' "$checks/checks.json" > "$checks/m.tmp" && mv "$checks/m.tmp" "$checks/checks.json"
jq '.checks[0].cmd = "test -f tests/t.txt && echo boom; exit 1"' "$checks/checks.json" > "$checks/m.tmp" && mv "$checks/m.tmp" "$checks/checks.json"
bash "$RC" "$checks/checks.json" red "$repo" >/dev/null; expect "the word ssh in a check name is not a remote command" 0 $?
jq '.checks = [.checks[0], .checks[0], .checks[0], .checks[0]]' "$checks/checks.json" > "$checks/m.tmp" && mv "$checks/m.tmp" "$checks/checks.json"
bash "$RC" "$checks/checks.json" red "$repo" >/dev/null; expect "more than 3 checks refused" 4 $?

# --- green mode
manifest 'test -f tests/t.txt' x
out=$(bash "$RC" "$checks/checks.json" green "$repo" "$(hashof)"); expect "green: passing check is green-ok" 0 $?
[ -f "$repo/tests/t.txt" ] && ok "green-ok: file left for the commit" || bad "green-ok: file left for the commit"
echo "$out" | grep -q '^INSTALLED tests/t.txt$' && ok "green-ok: INSTALLED line names the path" || bad "green-ok: INSTALLED line names the path"

# --- committed mode, on the file green left in place
h=$(hashof)
git -C "$repo" add tests/t.txt && git -C "$repo" -c user.name=t -c user.email=t@t commit -qm with-check
bash "$RC" "$checks/checks.json" committed "$repo" "$(git -C "$repo" rev-parse HEAD)" "$h" >/dev/null; expect "committed: identical check file is committed-ok" 0 $?
echo "weakened" > "$repo/tests/t.txt" && git -C "$repo" -c user.name=t -c user.email=t@t commit -qam weakened
bash "$RC" "$checks/checks.json" committed "$repo" "$(git -C "$repo" rev-parse HEAD)" "$h" >/dev/null; expect "committed: edited check file is committed-diff" 1 $?
cp "$checks/t.txt" "$tmp/t.bak" && echo "weakened" > "$checks/t.txt"
bash "$RC" "$checks/checks.json" committed "$repo" "$(git -C "$repo" rev-parse HEAD)" "$h" >/dev/null; expect "committed: source weakened too is tampered" 2 $?
cp "$tmp/t.bak" "$checks/t.txt"
git -C "$repo" rm -q tests/t.txt && git -C "$repo" -c user.name=t -c user.email=t@t commit -qm drop-check

manifest 'test -f tests/t.txt' x
h=$(hashof); echo "edited" >> "$checks/t.txt"
bash "$RC" "$checks/checks.json" green "$repo" "$h" >/dev/null; expect "green: check file edited since the red run is tampered" 2 $?
echo "check body" > "$checks/t.txt"
h=$(hashof); jq '.checks = []' "$checks/checks.json" > "$checks/m.tmp" && mv "$checks/m.tmp" "$checks/checks.json"
bash "$RC" "$checks/checks.json" green "$repo" "$h" >/dev/null; expect "green: checks list emptied since the red run is tampered" 2 $?
clean && ok "tampered: nothing installed" || bad "tampered: nothing installed"
printf 'echo boom; exit 1\n' > "$checks/probe.sh"
manifest "bash $checks/probe.sh" boom
h=$(hashof); printf 'exit 0\n' > "$checks/probe.sh"
bash "$RC" "$checks/checks.json" green "$repo" "$h" >/dev/null; expect "green: script called by path edited since the red run is tampered" 2 $?
rm -f "$checks/probe.sh"
manifest 'test -f tests/t.txt' x
out=$(bash "$RC" "$checks/checks.json" green "$repo"); expect "green: no HASH (old protocol) still runs" 0 $?
echo "$out" | grep -q '^NO-HASH' && ok "green: no HASH prints the NO-HASH warning" || bad "green: no HASH prints the NO-HASH warning"
rm -rf "$repo/tests"

manifest 'exit 1' x
bash "$RC" "$checks/checks.json" green "$repo" "$(hashof)" >/dev/null; expect "green: failing check is green-fail" 1 $?
clean && ok "green-fail: files uninstalled" || bad "green-fail: files uninstalled"

mkdir -p "$repo/tests" && echo mine > "$repo/tests/t.txt"
manifest 'true' x
bash "$RC" "$checks/checks.json" green "$repo" "$(hashof)" >/dev/null; expect "collision: existing dest refused" 3 $?
[ "$(cat "$repo/tests/t.txt")" = mine ] && ok "collision: existing file untouched" || bad "collision: existing file untouched"
rm -rf "$repo/tests"

manifest 'true' x '../evil.txt'
bash "$RC" "$checks/checks.json" green "$repo" "$(hashof)" >/dev/null; expect "dest escaping the repo refused" 4 $?
[ ! -e "$tmp/evil.txt" ] && ok "escape: nothing written outside" || bad "escape: nothing written outside"
manifest 'true' x '.git/hooks/pre-commit'
bash "$RC" "$checks/checks.json" green "$repo" "$(hashof)" >/dev/null; expect "dest inside .git refused" 4 $?
[ ! -e "$repo/.git/hooks/pre-commit" ] && ok ".git dest: nothing written" || bad ".git dest: nothing written"
manifest 'true' x './.git/hooks/post-commit'
bash "$RC" "$checks/checks.json" green "$repo" "$(hashof)" >/dev/null; expect "dest ./.git refused" 4 $?
[ ! -e "$repo/.git/hooks/post-commit" ] && ok "./.git dest: nothing written" || bad "./.git dest: nothing written"

# --- repo path with a space and brackets (real project folders have spaces)
odd="$tmp/My Projects [x]"; mkdir -p "$odd" && git -C "$odd" init -q && echo x > "$odd/a.txt" && git -C "$odd" add . \
  && git -C "$odd" -c user.name=t -c user.email=t@t commit -qm init
manifest 'test -f tests/t.txt && echo boom; exit 1' boom
bash "$RC" "$checks/checks.json" red "$odd" >/dev/null; expect "odd path: red-ok" 0 $?
[ -z "$(git -C "$odd" status --porcelain)" ] && [ ! -d "$odd/tests" ] && ok "odd path: tree clean, folder removed" || bad "odd path: tree clean, folder removed"

# --- no-repo mode and empty manifest
manifest 'test -f checks.json && echo boom; exit 1' boom
bash "$RC" "$checks/checks.json" red - >/dev/null; expect "no-repo: runs from the manifest folder" 0 $?
echo '{"task":"T2","checks":[],"files":[],"none":"copy change"}' > "$checks/checks.json"
out=$(bash "$RC" "$checks/checks.json" green "$repo"); expect "zero checks: RESULT none, no HASH needed" 0 $?
echo "$out" | grep -q 'RESULT none: copy change' || bad "zero checks: reason printed"

# --- drift.sh
DR=${DRIFT:-$here/drift.sh}
d=$tmp/drift; mkdir -p "$d/src" "$d/docs"
git -C "$d" init -q
printf 'Totals come from computeLegacyTotal, calling OLD_API_URL.\nkeepThisHelper stays.\nThe class RetryManager handles retries.\n' > "$d/CLAUDE.md"
printf 'The legacyExporter module writes CSV.\nThe priceFormatter module formats prices.\n' > "$d/docs/notes.md"
printf 'function computeLegacyTotal() {}\nfunction keepThisHelper() {}\nconst u = process.env.OLD_API_URL\n' > "$d/src/app.js"
echo 'export {}' > "$d/src/legacyExporter.js"
echo 'export const fmt = 1' > "$d/src/priceFormatter.js"
git -C "$d" add . && git -C "$d" -c user.name=t -c user.email=t@t commit -qm base
base=$(git -C "$d" rev-parse HEAD)
root=$(git -C "$d" rev-parse --show-toplevel); slug=$(printf '%s' "$root" | sed 's/[^A-Za-z0-9]/-/g')
fakehome=$tmp/home; mkdir -p "$fakehome/.claude/projects/$slug/memory"
echo 'Remember: computeLegacyTotal is the billing path.' > "$fakehome/.claude/projects/$slug/memory/note.md"
homeslug=$(printf '%s' "$fakehome" | sed 's/[^A-Za-z0-9]/-/g'); mkdir -p "$fakehome/.claude/projects/$homeslug/memory"
printf 'The worker calls runNightlySync every hour.\nRetryManager is flaky.\n' > "$fakehome/.claude/projects/$homeslug/memory/home.md"
printf 'package main\nfunc runNightlySync() {}\n' > "$d/src/sync.go"
git -C "$d" add src/sync.go && git -C "$d" -c user.name=t -c user.email=t@t commit -qm go && base=$(git -C "$d" rev-parse HEAD)
# the change: rename a function and an env var, delete a file, move a helper (removed + re-added),
# move a file to a new untracked path, rename a Go func, drop a prose line that says "class X" from
# a doc, and leave a big untracked file that mentions the removed Go name
printf 'function computeTotal() {}\nconst u = process.env.NEW_API_URL\n' > "$d/src/app.js"
printf 'function keepThisHelper() {}\n' > "$d/src/moved.js"   # untracked, as a builder's new file is at gate time
mkdir -p "$d/src/lib" && mv "$d/src/priceFormatter.js" "$d/src/lib/"   # moved: old path deleted, new path untracked
printf 'package main\nfunc runSync() {}\n' > "$d/src/sync.go"
printf 'Totals come from computeLegacyTotal, calling OLD_API_URL.\nkeepThisHelper stays.\n' > "$d/CLAUDE.md"   # prose line removed
{ echo 'runNightlySync'; head -c 1100000 /dev/zero | tr '\0' 'x'; } > "$d/dump.sql"   # untracked, over 1 MB: never read
git -C "$d" rm -q src/legacyExporter.js
out=$(HOME=$fakehome bash "$DR" "$d" "$base"); expect "drift: exits 0" 0 $?
echo "$out" | grep -q 'CLAUDE.md:1:.*\[computeLegacyTotal\]' && ok "drift: renamed function found in CLAUDE.md" || bad "drift: renamed function found in CLAUDE.md"
echo "$out" | grep -q 'CLAUDE.md:1:.*\[OLD_API_URL\]' && ok "drift: removed env var found" || bad "drift: removed env var found"
echo "$out" | grep -q 'docs/notes.md:1:.*\[legacyExporter\]' && ok "drift: deleted file found in docs" || bad "drift: deleted file found in docs"
echo "$out" | grep -q '^~/.claude/projects/.*/memory/note.md:1:.*\[computeLegacyTotal\]' && ok "drift: project memory searched" || bad "drift: project memory searched"
echo "$out" | grep -q 'keepThisHelper' && bad "drift: a name still present is not reported" || ok "drift: a name still present is not reported"
echo "$out" | grep -q 'priceFormatter' && bad "drift: a file moved to an untracked path is not reported" || ok "drift: a file moved to an untracked path is not reported"
echo "$out" | grep -q 'RetryManager' && bad "drift: a prose line removed from a doc yields no names" || ok "drift: a prose line removed from a doc yields no names"
echo "$out" | grep -q '^~/.claude/projects/.*/memory/home.md:1:.*\[runNightlySync\]' && ok "drift: home memory searched, Go func seen, big untracked file ignored" || bad "drift: home memory searched, Go func seen, big untracked file ignored"
echo "$out" | grep -q '^DRIFT: 5 hits$' && ok "drift: summary line counts hits" || bad "drift: summary line counts hits ($(echo "$out" | tail -1))"
printf 'Nothing relevant here.\n' > "$d/CLAUDE.md"; printf 'Nothing.\n' > "$d/docs/notes.md"; rm -rf "$fakehome/.claude/projects/$slug" "$fakehome/.claude/projects/$homeslug"
out=$(HOME=$fakehome bash "$DR" "$d" "$base")
echo "$out" | grep -q '^DRIFT: none' && ok "drift: no mention gives DRIFT: none" || bad "drift: no mention gives DRIFT: none"
HOME=$fakehome bash "$DR" "$d" not-a-sha >/dev/null; expect "drift: bad baseline refused" 4 $?

# --- stats.sh
ST=${STATS:-$here/stats.sh}
sf=$tmp/stats.tsv
today=$(date +%F)  # rows must stay inside the 30-day window stats.sh reports on
LOOPIT_STATS="$sf" bash "$ST" add $today app T1 opus 2 red-ok 1 yes 0 shipped; expect "stats: add a row" 0 $?
LOOPIT_STATS="$sf" bash "$ST" add $today app T2 sonnet 1 red-ok 2 no 0 shipped
LOOPIT_STATS="$sf" bash "$ST" add $today "my app" T3 opus 0 none 0 - 0 shipped 2>/dev/null; expect "stats: a value with a space is refused" 4 $?
LOOPIT_STATS="$sf" bash "$ST" add $today app T3 opus failed none 0 - 0 shipped 2>/dev/null; expect "stats: a non-numeric checks count is refused" 4 $?
LOOPIT_STATS="$sf" bash "$ST" add $today app T4 opus 0 none 0 - 0 shipped
LOOPIT_STATS="$sf" bash "$ST" add 2020-01-01 app OLD opus 1 red-ok 1 yes 0 shipped   # outside the window: never counted
[ "$(head -1 "$sf")" = "$(printf 'date\trepo\ttask\tbuilder_model\tchecks\tred\tgate_rounds\tfirst_pass\tdisputes\tstatus')" ] && ok "stats: header written once, with real tabs" || bad "stats: header written once, with real tabs"
[ "$(awk -F'\t' 'NF!=10' "$sf" | wc -l | tr -d ' ')" = 0 ] && ok "stats: every row has 10 columns" || bad "stats: every row has 10 columns"
out=$(LOOPIT_STATS="$sf" bash "$ST")
echo "$out" | grep -q 'last 30 days: 3 tasks, 2 with executable checks, first-pass 1/2 (50%)' && ok "stats: summary counts first-pass on tasks with checks" || bad "stats: summary ($(echo "$out" | head -1))"


echo; [ "$fails" -eq 0 ] && { echo "all green"; exit 0; }
echo "$fails failing"; exit 1
