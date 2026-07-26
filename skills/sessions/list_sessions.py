#!/usr/bin/env python3
"""List recent Claude Code sessions, newest first.

Reads ~/.claude/projects/*/*.jsonl and prints:
  - project name (from cwd, basename)
  - session UUID (for `claude --resume <id>`)
  - first user prompt (short description)
  - last activity timestamp
Usage:
  list_sessions.py             # last 7 days, flat chronological list
  list_sessions.py --grouped   # group per project so parallel sessions are visible
  list_sessions.py --days 30   # widen the window
  list_sessions.py --all       # no time filter
  list_sessions.py --project myapp       # filter by project name substring
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

PROJECTS_DIR = Path.home() / ".claude" / "projects"


def parse_session(path: Path):
    """Return (cwd, session_id, first_user_prompt, last_ts) or None."""
    session_id = path.stem
    cwd = None
    first_prompt = None
    last_ts = None
    try:
        with path.open("r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue

                ts = obj.get("timestamp")
                if ts:
                    last_ts = ts

                if cwd is None and obj.get("cwd"):
                    cwd = obj["cwd"]

                if first_prompt is None and obj.get("type") == "user":
                    msg = obj.get("message") or {}
                    content = msg.get("content")
                    # content may be a string or a list of blocks
                    if isinstance(content, str):
                        text = content
                    elif isinstance(content, list):
                        parts = []
                        for block in content:
                            if isinstance(block, dict) and block.get("type") == "text":
                                parts.append(block.get("text", ""))
                            elif isinstance(block, str):
                                parts.append(block)
                        text = " ".join(parts)
                    else:
                        text = ""
                    text = text.strip()
                    # Skip command/system-style prompts when looking for the human intent
                    if text and not text.startswith("<") and not text.startswith("Caveat:"):
                        first_prompt = text
    except OSError:
        return None

    return cwd, session_id, first_prompt, last_ts


def fmt_ts(ts: str | None) -> tuple[str, datetime | None]:
    if not ts:
        return ("(no timestamp)", None)
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return (ts, None)
    local = dt.astimezone()
    return (local.strftime("%Y-%m-%d %H:%M"), dt)


def shorten(text: str | None, width: int = 110) -> str:
    if not text:
        return "(no user prompt found)"
    text = " ".join(text.split())
    if len(text) > width:
        return text[: width - 1] + "…"
    return text


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--days", type=int, default=7, help="Only show sessions modified within N days (default: 7)")
    ap.add_argument("--all", action="store_true", help="Show all sessions (ignore --days)")
    ap.add_argument("--project", default=None, help="Filter by project name substring (case-insensitive)")
    ap.add_argument("--grouped", action="store_true", help="Group by project instead of the default flat chronological list")
    args = ap.parse_args()

    if not PROJECTS_DIR.exists():
        print(f"No Claude projects dir at {PROJECTS_DIR}", file=sys.stderr)
        return 1

    cutoff: datetime | None = None
    if not args.all:
        cutoff = datetime.now(timezone.utc) - timedelta(days=args.days)

    rows = []
    for jsonl in PROJECTS_DIR.glob("*/*.jsonl"):
        mtime = datetime.fromtimestamp(jsonl.stat().st_mtime, tz=timezone.utc)
        if cutoff and mtime < cutoff:
            continue
        parsed = parse_session(jsonl)
        if not parsed:
            continue
        cwd, sid, prompt, last_ts = parsed
        if cwd is None:
            # Fall back to decoding the parent dir name
            cwd = "/" + jsonl.parent.name.lstrip("-").replace("-", "/")
        project = os.path.basename(cwd) or cwd
        if args.project and args.project.lower() not in project.lower():
            continue
        ts_str, ts_dt = fmt_ts(last_ts)
        # Prefer the in-file timestamp; fall back to mtime
        sort_key = ts_dt or mtime
        rows.append({
            "project": project,
            "cwd": cwd,
            "sid": sid,
            "prompt": prompt,
            "ts_str": ts_str,
            "sort_key": sort_key,
        })

    if not rows:
        print("No sessions found in the selected window.")
        return 0

    if not args.grouped:
        rows.sort(key=lambda r: r["sort_key"], reverse=True)
        width = max(len(r["project"]) for r in rows)
        for r in rows:
            print(f"[{r['ts_str']}]  {r['project']:<{width}}  {r['sid']}")
            print(f"    → {shorten(r['prompt'])}")
        print(f"\n({len(rows)} sessions) resume: claude --resume <id>")
        return 0

    # Group by project, sort projects by most-recent activity, sessions inside by recency
    groups: dict[str, list] = {}
    for r in rows:
        groups.setdefault(r["project"], []).append(r)

    project_order = sorted(
        groups.items(),
        key=lambda kv: max(r["sort_key"] for r in kv[1]),
        reverse=True,
    )

    for project, sessions in project_order:
        sessions.sort(key=lambda r: r["sort_key"], reverse=True)
        cwd = sessions[0]["cwd"]
        header = f"\n=== {project}"
        if len(sessions) > 1:
            header += f"  ({len(sessions)} sessions)"
        print(header)
        print(f"    cd {cwd}")
        for r in sessions:
            print(f"    [{r['ts_str']}]  {r['sid']}")
            print(f"        → {shorten(r['prompt'])}")
            print(f"        resume: claude --resume {r['sid']}")
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
