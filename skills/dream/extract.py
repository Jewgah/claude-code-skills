#!/usr/bin/env python3
"""Pull the raw material for /dream out of Claude Code transcripts. Read-only, stdlib only.

  SAID  what the user typed (origin.kind == "human": typed, queued, slash commands, accepted suggestions)
  ERR   a failed tool call, with the call that caused it (subagent transcripts included, tagged "sub")
  DENY  a call stopped by a hook gate, the auto-mode classifier or the user's own refusal
Entries older than --days are dropped one by one, not file by file. A summary of the most
frequent ERR and DENY groups closes the file.

usage: extract.py OUT.txt [--days 7] [--project=SUBSTRING|EXACT-FOLDER|all]
--project defaults to the transcript folder of the current directory.
Self-check: extract.py --selftest
"""
import argparse, collections, difflib, glob, json, os, re, sys, tempfile
from datetime import datetime, timezone

ROOT = os.path.expanduser("~/.claude/projects")
PASTE = re.compile(r"<pasted_content[^>]*>.*?</pasted_content[^>]*>", re.S)
CMD = re.compile(r"<command-name>(.*?)</command-name>(?:.*?<command-args>(.*?)</command-args>)?", re.S)
DENIED = ("PreToolUse:", "Permission for this action was denied", "The user doesn't want to proceed",
          "The user doesn't want to take this action")

def slug(path):  # Claude Code names a project folder after its cwd, every non-alphanumeric char -> "-"
    return re.sub(r"[^A-Za-z0-9]", "-", path)

def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text")
    return ""

def human_text(raw):
    """The user's words from one human entry: a paste becomes [paste], a slash command keeps its args."""
    m = CMD.search(raw)
    if m:
        return f"{m.group(1).strip()} {(m.group(2) or '').strip()}".strip()
    t = " ".join(PASTE.sub(" [paste] ", raw).split())
    return t if len(t) <= 450 else f"{t[:150]} [...] {t[-300:]}"  # his reaction comes last

def when(e):
    try:
        return datetime.fromisoformat(e["timestamp"].replace("Z", "+00:00")).timestamp()
    except (KeyError, TypeError, ValueError, AttributeError):
        return None

def scan(path, since, out, seen, groups, sub):
    proj = path[len(ROOT) + 1:].split("/")[0]
    sid = os.path.basename(path)[:8] if not sub else path.split("/")[-3][:8] + "/sub"
    calls, n = {}, collections.Counter()
    try:
        fh = open(path, errors="replace")
    except OSError as err:
        print(f"skipped {path}: {err}", file=sys.stderr)
        return n
    with fh:
        for line in fh:
            try:
                e = json.loads(line)
            except ValueError:  # a half-written last line from a live session
                continue
            if not isinstance(e, dict):
                continue
            msg = e.get("message") if isinstance(e.get("message"), dict) else {}
            content = msg.get("content")
            if e.get("type") == "assistant" and isinstance(content, list):
                for c in content:
                    if isinstance(c, dict) and c.get("type") == "tool_use":
                        calls[c.get("id")] = f'{c.get("name")} {json.dumps(c.get("input"))[:200]}'
            t = when(e)
            if t is None or t < since:
                continue
            ts = e["timestamp"][:16]
            if e.get("type") == "user" and isinstance(content, list):
                for c in content:
                    if not (isinstance(c, dict) and c.get("type") == "tool_result" and c.get("is_error")):
                        continue
                    body = c.get("content")
                    body = " ".join((body if isinstance(body, str) else text_of(body)).split())
                    kind = "DENY" if any(d in body[:300] for d in DENIED) else "ERR "
                    call = calls.get(c.get("tool_use_id"), "?")
                    out.write(f"{kind} {proj} {sid} {ts} | {call}\n     -> {body[:240]}\n")
                    groups[kind][f"{call.split(' ')[0]}: {body[:70]}"] += 1
                    n[kind] += 1
            if sub:
                continue  # a subagent's "user" turns are the parent's prompts, never the user
            if e.get("type") == "user" and not e.get("isMeta"):
                origin, raw, key = e.get("origin"), text_of(content), e.get("uuid")
            elif e.get("type") == "attachment" and isinstance(e.get("attachment"), dict):
                a = e["attachment"]  # a message typed while the model was busy
                if a.get("type") != "queued_command":
                    continue
                origin, raw, key = a.get("origin"), a.get("prompt") if isinstance(a.get("prompt"), str) else "", None
            else:
                continue
            if not (isinstance(origin, dict) and origin.get("kind") == "human"):
                continue
            said = human_text(raw)
            # a queued message is stored twice in one file (attachment, then user entry); a resumed
            # session copies history under the same uuid. Same words in two sessions both count.
            if not said or key in seen or (path, said) in seen:
                continue
            seen.update({key, (path, said)} - {None})
            out.write(f"SAID {proj} {sid} {ts} | {said}\n")
            n["SAID"] += 1
    return n

def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--days", type=float, default=7)
    ap.add_argument("--project", default=slug(os.getcwd()))
    a = ap.parse_args(argv)
    out_path = os.path.abspath(os.path.expanduser(a.out))
    if not out_path.endswith(".txt") or out_path.startswith(ROOT + "/") or not 0 < a.days < 3650:
        sys.exit(f"refused: OUT must be a .txt outside {ROOT} and --days a number of days (got {a.out!r}, {a.days})")
    since = datetime.now(timezone.utc).timestamp() - a.days * 86400
    folders = sorted(d for d in os.listdir(ROOT) if os.path.isdir(os.path.join(ROOT, d)))
    def wanted(folder):  # "all", an exact folder name ("-Users-..."), or a substring ("myapp")
        p = a.project
        return p == "all" or (folder == p if p.startswith("-") else p.lower() in folder.lower())
    picked = [d for d in folders if wanted(d)]
    files = [(f, sub) for d in picked
             for f, sub in [(x, False) for x in glob.glob(f"{ROOT}/{glob.escape(d)}/*.jsonl")] +
                           [(x, True) for x in glob.glob(f"{ROOT}/{glob.escape(d)}/*/subagents/*.jsonl")]
             if os.path.exists(f) and os.path.getmtime(f) >= since]
    total, seen, groups = collections.Counter(), set(), {"ERR ": collections.Counter(), "DENY": collections.Counter()}
    with open(out_path, "w") as out:
        for f, sub in sorted(files, key=lambda x: os.path.getmtime(x[0]) if os.path.exists(x[0]) else 0):
            total += scan(f, since, out, seen, groups, sub)
        for kind, label in (("ERR ", "most frequent failures"), ("DENY", "most frequent denials")):
            out.write(f"\n== {label} (tool: error start) ==\n")
            for k, c in groups[kind].most_common(15):
                out.write(f"{c:5d}  {k}\n")
    top = sum(1 for _, s in files if not s)
    print(f"{len(picked)} folders, {top} transcripts + {len(files) - top} subagent files: {total['SAID']} SAID, "
          f"{total['ERR ']} ERR, {total['DENY']} DENY -> {out_path}")
    if not picked:
        near = difflib.get_close_matches(a.project, folders, n=3, cutoff=0.5)
        print(f"no folder matches --project {a.project!r}; closest: {', '.join(near) or 'none'}")

def selftest():
    d = tempfile.mkdtemp()
    p = os.path.join(d, "s.jsonl")
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    rows = [
        {"type": "user", "timestamp": now, "uuid": "u1", "origin": {"kind": "human"}, "message": {"content": "no, wrong path"}},
        {"type": "user", "timestamp": now, "uuid": "u1", "origin": {"kind": "human"}, "message": {"content": "no, wrong path"}},
        {"type": "user", "timestamp": "2020-01-01T00:00:00Z", "uuid": "u0", "origin": {"kind": "human"}, "message": {"content": "too old"}},
        {"type": "user", "timestamp": now, "entrypoint": "sdk-cli", "message": {"content": "never do X (a script)"}},
        {"type": "user", "timestamp": now, "uuid": "u2", "origin": {"kind": "human"},
         "message": {"content": "<pasted_content id=1>quote</pasted_content id=1> explique en francais"}},
        {"type": "user", "timestamp": now, "uuid": "u3", "origin": {"kind": "human"},
         "message": {"content": "<command-message>x</command-message><command-name>/loopit</command-name><command-args>reorder first</command-args>"}},
        {"type": "attachment", "timestamp": now, "attachment": {"type": "queued_command", "prompt": "typed while busy", "origin": {"kind": "human"}}},
        {"type": "assistant", "timestamp": now, "message": {"content": [{"type": "tool_use", "id": "t1", "name": "Bash", "input": {"command": "ls"}}]}},
        {"type": "user", "timestamp": now, "message": {"content": [{"type": "tool_result", "tool_use_id": "t1", "is_error": True, "content": "Exit code 1 boom"}]}},
        {"type": "user", "timestamp": now, "message": {"content": [{"type": "tool_result", "tool_use_id": "t1", "is_error": True, "content": "PreToolUse:Bash hook error: gate"}]}},
        "not a dict", {"type": "user", "message": {"content": [1, None]}},
    ]
    with open(p, "w") as f:
        f.write("\n".join(json.dumps(r) for r in rows) + "\n{half")
    import io
    buf, groups = io.StringIO(), {"ERR ": collections.Counter(), "DENY": collections.Counter()}
    global ROOT
    ROOT = d
    n = scan(p, datetime.now(timezone.utc).timestamp() - 86400, buf, set(), groups, False)
    s = buf.getvalue()
    assert n["SAID"] == 4 and n["ERR "] == 1 and n["DENY"] == 1, (n, s)
    assert "too old" not in s and "a script" not in s and s.count("wrong path") == 1, s
    assert "[paste] explique en francais" in s and "/loopit reorder first" in s and "typed while busy" in s, s
    q = os.path.join(d, "t.jsonl")  # the same words typed in another session count again
    with open(q, "w") as f:
        f.write(json.dumps(dict(rows[0], uuid="u9")) + "\n")
    seen, buf2 = set(), io.StringIO()
    scan(p, 0, io.StringIO(), seen, groups, False)
    assert scan(q, 0, buf2, seen, groups, False)["SAID"] == 1, buf2.getvalue()
    assert slug("/Users/x/My Projects/web.app") == "-Users-x-My-Projects-web-app"
    print("selftest ok")

if __name__ == "__main__":
    selftest() if sys.argv[1:] == ["--selftest"] else main(sys.argv[1:])
