---
name: sessions
description: List recent Claude Code sessions across all projects with project name, session ID, resume command, and short description of what the session was about. Handles multiple parallel sessions per project. Use when the user wants to find, resume, or recall a previous Claude conversation — especially before/after a reboot.
---

# List recent Claude Code sessions

When invoked, run the helper script and pass its output through.

## Step 1 — pick the mode from the skill argument

| Argument | Command | View |
|---|---|---|
| *(none)* or `recent` | `python3 ~/.claude/skills/sessions/list_sessions.py` | **default** — one flat list, newest first, across all projects |
| `project` (or "grouped", "by project") | `python3 ~/.claude/skills/sessions/list_sessions.py --grouped` | grouped per project, so parallel sessions are visible |

Other arguments (use only if the user asks):

- `--days 30` — widen the window to 30 days (default 7)
- `--all` — show everything ever recorded
- `--project <substring>` — **filter** by project name, case-insensitive (e.g. `--project myapp`). Unrelated to the `project` grouping mode above; combines with both views.

## Step 2 — present the output

Default mode prints one flat chronological list — `[timestamp] project session-id` + the first prompt — with the resume hint once at the bottom.

`--grouped` mode prints: project header → `cd` line → one block per session with timestamp, session UUID, first user prompt, and the exact `claude --resume <id>` command.

After running it:
- Pass through the output as-is — do not re-summarise every session, the user wants the raw list.
- If the user names a specific topic or project, point out the matching session(s) at the top.
- If there are many sessions for one project, note it ("3 parallel sessions for X today") so the user knows multiple threads exist.
- If the user is about to reboot, remind them: `claude --resume <session-id>` restores full context; `claude --resume` alone opens an interactive picker scoped to the **current working directory**, so they must `cd` into the project first if they use the picker form.

## Notes on the data

- Sessions live in `~/.claude/projects/<encoded-cwd>/<session-uuid>.jsonl`.
- One `.jsonl` = one session. Multiple files in the same project dir = parallel sessions.
- The script extracts the first real user prompt as the "description" — it skips system/caveat blocks.
- Image-only prompts show as `[Image #1]`; that's expected, not a bug.
- The encoded directory name (`-Users-you-projects-myapp`) isn't always the same as the real `cwd`; the script reads the `cwd` field from inside the JSONL for accuracy.
