---
description: Leaderboard of your most-used skills from the durable usage log (survives transcript cleanup)
argument-hint: "[days N] [project <name>] [history] [--all] (blank = log only, top 25)"
---

Show a ranked leaderboard of skill / slash-command usage.

**Source of truth:** the durable log at `~/.claude/skill-usage.log`, written by the `log-skill.sh` hooks (UserPromptSubmit = typed `/cmd`, PreToolUse:Skill = natural-language-triggered). It survives the 365-day transcript cleanup, so it only grows. The log begins the day you install the hooks — anything earlier lives only in transcripts.

Steps:

1. If the log is missing/empty, say it's only been accumulating since the hooks were installed and there's nothing logged yet. Then offer the `history` mode below.

2. Parse `$ARGUMENTS` for optional filters:
   - `days N` → keep only entries from the last N days
   - `project <name>` → keep only entries whose cwd contains `<name>` (case-insensitive)
   - `history` → ALSO count usage from BEFORE the log started, by scanning transcripts (entries dated before the log's first line, so no double-count with the log).
   - `--all` (or `all`) → show the FULL ranking with no cutoff (drop the `head -25` in the commands below). Default is top 25.

   **Artifact filter (always on):** real skill names match `^[A-Za-z0-9:_-]+$`. The transcript scan can pick up its own diagnostic `grep` patterns recorded in transcripts (e.g. `\?toy-repos`, `\?\(jira\|review\|...\)`), so every pipeline below pipes through `grep -E '^[A-Za-z0-9:_-]+$'` to drop them. (The durable log is already clean — `log-skill.sh` only writes parsed names — but apply it uniformly.)

3. Tally the log by skill name. Base command (adapt for the `days`/`project` filters; drop `| head -25` when `--all`):
   ```bash
   log="$HOME/.claude/skill-usage.log"
   awk -F'\t' '$2 ~ /^[A-Za-z0-9:_-]+$/ {c[$2]++; t[$2"\t"$3]++; if($1>last[$2]) last[$2]=$1}
     END{for(k in c) printf "%d\t%s\t%s\n", c[k], k, last[k]}' "$log" | sort -rn | head -25
   ```

4. For `history` mode, prepend transcript-derived counts (only for the window before the log's earliest timestamp) using BOTH invocation paths — this is the corrected method:
   ```bash
   cd ~/.claude/projects
   { find . -name '*.jsonl' -print0 | xargs -0 grep -ho '<command-name>/\?[^<]*</command-name>' 2>/dev/null
     find . -name '*.jsonl' -print0 | xargs -0 grep -ho '"name":"Skill","input":{"skill":"[^"]*"' 2>/dev/null | sed 's/.*"skill":"//; s/"$//'
   } | sed -E 's#</?command-name>##g; s#^/##' \
     | grep -E '^[A-Za-z0-9:_-]+$' \
     | grep -vE '^(model|compact|resume|rename|exit|clear|plan|effort|mcp|status|doctor|context|EnterPlanMode|ExitPlanMode|init)$' \
     | sort | uniq -c | sort -rn | head -25
   ```
   The `grep -E '^[A-Za-z0-9:_-]+$'` drops self-referential grep-pattern artifacts. Drop `| head -25` when `--all`. Note in the output that transcript history is approximate (compaction drops some) and is a floor.

5. Present a markdown table: **Skill | Uses | Share % | Last used** (and typed-vs-nl split when interesting). With `--all`, show every skill (no truncation) and append a count of distinct skills. End with total invocations and the date range covered. Exclude built-in CLI commands (model, compact, resume, rename, exit, clear, plan, effort, mcp, status, doctor, context) unless the user asks for them.

$ARGUMENTS
