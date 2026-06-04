#!/usr/bin/env bash
# init-agents :: PreToolUse(Bash) guard (OPT-IN).
# Blocks a small set of destructive commands. Reads hook JSON on STDIN.
# exit 2 = block the tool call (Claude sees the stderr message as the reason).

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$cmd" ] && exit 0

block() { echo "Blocked by .claude/hooks/guard.sh: $1" >&2; exit 2; }

case "$cmd" in
  # Deliberately conservative: blocks ANY absolute-path or home recursive delete
  # (substring match), not just "/". Over-blocking is the point — the agent sees
  # the reason and can ask you to run it yourself. Relative-path rm -rf passes.
  *"rm -rf /"*|*"rm -rf ~"*|*"rm -rf /*"*) block "recursive delete of an absolute/home path — run it yourself if intended" ;;
  *"git push --force"*|*"git push -f"*)     block "force-push (use --force-with-lease after review)" ;;
  *"git reset --hard"*)                      block "hard reset (discards work — run it yourself if intended)" ;;
  *":(){ :|:&};:"*)                          block "fork bomb" ;;
esac

exit 0
