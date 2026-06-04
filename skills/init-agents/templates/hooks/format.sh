#!/usr/bin/env bash
# init-agents :: PostToolUse(Edit|Write) formatter.
# Claude Code passes hook data as JSON on STDIN — there is NO ${file_path}
# substitution in the command string, so we read it here with jq.
# Non-blocking by contract: always exit 0; a missing/failing formatter must
# never block an edit.

input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
[ -n "$file" ] && [ -f "$file" ] || exit 0

# Run the formatter but swallow all failures (binary missing, syntax error, …).
format() { "$@" >/dev/null 2>&1 || true; }

case "$file" in
  # {{KEEP ONLY THE ARMS FOR DETECTED STACKS; fill the formatter command}}
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.json|*.css|*.scss|*.md|*.yml|*.yaml)
    format {{FMT_JS}} "$file" ;;
  *.php) format {{FMT_PHP}} "$file" ;;
  *.py)  format {{FMT_PY}}  "$file" ;;
  *.go)  format gofmt -w "$file" ;;
  *.rs)  format rustfmt "$file" ;;
esac

exit 0
