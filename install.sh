#!/usr/bin/env bash
# Installs the review-gated workflow into ~/.claude:
#   skills + commands  -> ~/.claude/skills, ~/.claude/commands
#   hooks              -> ~/.claude/hooks
#   hook wiring        -> merged into ~/.claude/settings.json (backed up first)
# Idempotent: re-running skips anything already present.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE="$HOME/.claude"
S="$CLAUDE/settings.json"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required (brew install jq / apt install jq)."; exit 1; }

mkdir -p "$CLAUDE/skills" "$CLAUDE/commands" "$CLAUDE/hooks"

installed=(); skipped=()

for d in "$REPO"/skills/*/; do
  n="$(basename "$d")"
  if [ -e "$CLAUDE/skills/$n" ]; then skipped+=("skill /$n (exists)")
  else cp -r "$d" "$CLAUDE/skills/$n"; installed+=("skill /$n"); fi
done

for f in "$REPO"/commands/*.md; do
  n="$(basename "$f")"
  if [ -e "$CLAUDE/commands/$n" ]; then skipped+=("command /${n%.md} (exists)")
  else cp "$f" "$CLAUDE/commands/$n"; installed+=("command /${n%.md}"); fi
done

for f in "$REPO"/hooks/*; do
  n="$(basename "$f")"
  # log-skill.sh lives at ~/.claude/log-skill.sh in the reference setup; keep hooks/ tidy instead.
  cp "$f" "$CLAUDE/hooks/$n"; chmod +x "$CLAUDE/hooks/$n"; installed+=("hook $n")
done

# ---- wire the hooks into settings.json -------------------------------------
[ -f "$S" ] || echo '{}' > "$S"
cp "$S" "$S.bak-$(date +%Y%m%d%H%M%S)"

# add <event> <matcher|""> <command> <timeout|""> <async:true|"">
add() {
  local event="$1" matcher="$2" cmd="$3" timeout="$4" async="$5" tmp
  # Already wired? Compare parsed values — grep would miss it, the file stores \" escaped.
  if jq -e --arg e "$event" --arg c "$cmd" \
        '[.hooks[$e][]?.hooks[]?.command] | index($c) != null' "$S" >/dev/null; then
    skipped+=("hook wiring $event ${matcher:-*} (already wired)"); return
  fi
  tmp="$(mktemp)"
  jq --arg e "$event" --arg m "$matcher" --arg c "$cmd" \
     --argjson t "${timeout:-null}" --argjson a "${async:-null}" '
    def entry: {type:"command", command:$c}
      | if $t == null then . else . + {timeout:$t} end
      | if $a == null then . else . + {async:$a} end;
    def block: (if $m == "" then {} else {matcher:$m} end) + {hooks:[entry]};
    .hooks = (.hooks // {}) | .hooks[$e] = ((.hooks[$e] // []) + [block])
  ' "$S" > "$tmp" && mv "$tmp" "$S"
  installed+=("hook wiring $event ${matcher:-*}")
}

H="\$HOME/.claude/hooks"
add UserPromptSubmit ""             "bash \"$H/log-skill.sh\" prompt"        ""   true
add PreToolUse       "Skill"        "bash \"$H/log-skill.sh\" tool"          ""   true
add PreToolUse       "ExitPlanMode" "node \"$H/plan-review-gate.mjs\""       10   ""
add PreToolUse       "Bash"         "bash \"$H/commit-review-gate.sh\""      10   ""

# statusLine: only claim it if unset — never clobber an existing one.
if [ "$(jq -r '.statusLine // empty' "$S")" = "" ]; then
  tmp="$(mktemp)"
  jq --arg c "bash \"$H/statusline.sh\"" '.statusLine = {type:"command", command:$c}' "$S" > "$tmp" && mv "$tmp" "$S"
  installed+=("statusLine (branch | dirty | review state)")
else
  skipped+=("statusLine (you already have one — see hooks/statusline.sh to merge by hand)")
fi

jq empty "$S" || { echo "ERROR: settings.json is now invalid — restore the .bak file."; exit 1; }

echo "Installed:"; for i in "${installed[@]:-}"; do [ -n "$i" ] && echo "  + $i"; done
if [ "${#skipped[@]}" -gt 0 ]; then echo "Skipped:"; for s in "${skipped[@]}"; do echo "  - $s"; done; fi
cat <<'EOF'

Done. Start a NEW Claude Code session to load the hooks and skills.

Verify (in a scratch git repo with an uncommitted change):
  1. Ask Claude to make a plan (plan mode) -> it must run /review-plan before showing it.
  2. Ask Claude to commit -> it must be blocked until /review or /review-deep has run.
EOF
