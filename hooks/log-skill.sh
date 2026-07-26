#!/usr/bin/env bash
# Logs skill / slash-command usage to ~/.claude/skill-usage.log
# Invoked by Claude Code hooks. Reads the hook event JSON on stdin.
#   Usage: log-skill.sh <mode>     mode = prompt | tool
#     prompt → UserPromptSubmit: captures a typed "/command ..."
#     tool   → PreToolUse(Skill): captures a natural-language-triggered skill
# Appends one tab-separated line: <iso8601>\t<name>\t<source>\t<cwd>
# Always exits 0 so it never blocks prompt submission or tool use.

mode="$1"
log="$HOME/.claude/skill-usage.log"
ts="$(date +%Y-%m-%dT%H:%M:%S)"
input="$(cat)"
name=""
src=""

case "$mode" in
  tool)
    name="$(printf '%s' "$input" | jq -r '.tool_input.skill // empty' 2>/dev/null)"
    src="nl"
    ;;
  prompt)
    # ponytail: name must end at whitespace or EOL — a following "/" means a pasted path (/Users/...), not a command
    name="$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null \
      | sed -n '1s#^[[:space:]]*/\([A-Za-z0-9:_-]\{1,\}\)\([[:space:]].*\)\{0,1\}$#\1#p')"
    src="typed"
    ;;
esac

cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"

[ -n "$name" ] && printf '%s\t%s\t%s\t%s\n' "$ts" "$name" "$src" "$cwd" >> "$log"
exit 0
