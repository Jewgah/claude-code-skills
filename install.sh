#!/usr/bin/env bash
# Install all skills and commands from this repo into ~/.claude/
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
COMMANDS_DIR="$HOME/.claude/commands"

mkdir -p "$SKILLS_DIR" "$COMMANDS_DIR"

installed=()
skipped=()

for skill in "$REPO_DIR"/skills/*/; do
  name="$(basename "$skill")"
  if [ -e "$SKILLS_DIR/$name" ]; then
    skipped+=("skill $name (already exists — remove ~/.claude/skills/$name to reinstall)")
  else
    cp -r "$skill" "$SKILLS_DIR/$name"
    installed+=("skill /$name")
  fi
done

for cmd in "$REPO_DIR"/commands/*.md; do
  name="$(basename "$cmd" .md)"
  if [ -e "$COMMANDS_DIR/$name.md" ]; then
    skipped+=("command $name (already exists — remove ~/.claude/commands/$name.md to reinstall)")
  else
    cp "$cmd" "$COMMANDS_DIR/$name.md"
    installed+=("command /$name")
  fi
done

echo "Installed:"
for i in "${installed[@]:-}"; do [ -n "$i" ] && echo "  ✓ $i"; done
if [ "${#skipped[@]}" -gt 0 ]; then
  echo "Skipped:"
  for s in "${skipped[@]}"; do echo "  - $s"; done
fi
echo
echo "Start a new Claude Code session to pick them up."
