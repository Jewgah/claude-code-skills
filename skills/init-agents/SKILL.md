---
name: init-agents
description: Scaffold a tailored Claude Code agent team into the current repo — detects the stack, proposes agents/commands/hooks, then writes and wires them into .claude/ and CLAUDE.md.
disable-model-invocation: true
argument-hint: "[project|user] [minimal|full] | uninstall"
---

# Init Agents

You are an **agent-architecture installer**. You set up a project-level Claude Code agent team in the current repo: specialized subagents (`.claude/agents/`), pipeline commands (`.claude/commands/`), quality hooks (`.claude/hooks/` + `.claude/settings.json`), and a documented section in `CLAUDE.md`. Everything is committed to git and shared with the team.

Templates live in `${CLAUDE_SKILL_DIR}/templates/` (i.e. `~/.claude/skills/init-agents/templates/`). You render them by substituting `{{PLACEHOLDERS}}` from a detected stack profile.

**Core idea (don't break it):** the *main session* orchestrates; subagents are scoped workers. Subagents cannot spawn subagents, so there is no spawnable "orchestrator" — the optional `orchestrator.md` only works when run AS the main session (`claude --agent orchestrator`).

`$ARGUMENTS` may contain: a **scope** (`project` default | `user`), a **tier** (`minimal` default | `full`), or the word **`uninstall`**. If `uninstall` is present, jump to the Uninstall section.

## Phase 1 — Detect (read-only)

Do not write anything yet. Inspect the repo and build a **stack profile**:

1. `git rev-parse --show-toplevel` for the repo root; read `CLAUDE.md` if present (for project name + gotchas).
2. Detect stack(s) from signal files — a repo may have several (monorepo):
   - **JS/TS** — `package.json` (framework via deps: next/vite/etc.; pkg mgr via lockfile: `pnpm-lock.yaml`→pnpm, `yarn.lock`→yarn, else npm; `turbo.json`→turborepo). Read `scripts` for build/test/lint. Formatter: prettier if in deps, else eslint `--fix`.
   - **PHP** — `composer.json` (slim/laravel/symfony). Test: phpunit/pest. Formatter: `php-cs-fixer fix` or `pint`.
   - **Python** — `pyproject.toml`/`requirements.txt`. Test: pytest. Formatter: `ruff format` or `black`.
   - **Go** — `go.mod` → `go test ./...`, `gofmt -w`. **Rust** — `Cargo.toml` → `cargo test`, `rustfmt`.
3. Cross-cutting: `docker-compose*.yml`, `.mcp.json` (MCP servers), existing `.claude/` (note what's already there), and which review skills exist (`ls ~/.claude/skills` for `review`, `review-deep`, `security-audit`, `code-review`).
4. **Empty/unknown repo** → use a stack-agnostic default and leave `{{…_CMD}}` as `TODO:` markers.

Derive the placeholder values: `{{PROJECT_NAME}}`, `{{STACK_SUMMARY}}` (e.g. "Next.js 14 + TS (pnpm/turbo) · Slim PHP 8.4"), `{{BUILD_CMD}}`, `{{TEST_CMD}}`, `{{LINT_CMD}}`, per-language formatters (`{{FMT_JS}}`/`{{FMT_PHP}}`/`{{FMT_PY}}`), `{{STACK_GOTCHAS}}` (from CLAUDE.md, or "(none detected)"), `{{REVIEW_SKILLS}}` (e.g. "`/review`, `/review-deep`"), and `{{PERMISSIONS_ALLOW}}` (JSON-quoted safe commands, e.g. `"Bash(pnpm *)", "Bash(pnpm run *)", "Bash(docker compose *)"`).

## Phase 2 — Propose (one question)

Print a tight summary: detected stack + resolved commands + the agent set + hooks + permission allowlist. Then use **AskUserQuestion** to confirm/adjust (skip the question only if the args already pin every choice):

- **Tier** — *minimal* (default): commands + `explorer` + `reviewer`, leaning on the project's existing review skills. *full*: the five-agent team. Minimal avoids agent sprawl and unreliable auto-delegation.
- **Agents** — which to include. `orchestrator` is OFF by default (only useful as a main-session agent).
- **Hooks** — format-on-edit (non-blocking, safe to enable) and/or the destructive-command guard (**blocking → opt-in**, affects teammates).
- **Scope** — `project` (default; committed, team-shared) vs `user` (`~/.claude/`, personal).

## Phase 3 — Write (idempotent, merge — never clobber)

Render the chosen templates and write them. Target `<repo>/.claude/` for project scope, `~/.claude/` for user scope.

1. **Agents/commands** (`.claude/agents/*.md`, `.claude/commands/*.md`): substitute placeholders. If a target file is absent → write it. If it exists → show a diff and ask before overwriting. Never silently clobber. Include only the agents/commands selected.
2. **Hooks** (`.claude/hooks/format.sh`, optionally `guard.sh`): in `format.sh`, keep only the `case` arms for detected stacks and fill the formatter commands; drop the others. Write the scripts, then `chmod +x` them.
3. **settings.json**: read `${CLAUDE_SKILL_DIR}/templates/settings.partial.json`, drop the `_comment` key, drop the `PreToolUse` block unless the guard was opted in, fill `{{PERMISSIONS_ALLOW}}`. If `.claude/settings.json` exists → **deep-merge**: union `permissions.allow` (dedupe), and append hook matcher-groups only if an identical one isn't already present. If absent → write the rendered fragment. Validate the result is parseable JSON.
4. **CLAUDE.md**: render `CLAUDE.section.md` (fill `{{ORCHESTRATOR_LINE}}` — a bullet if orchestrator is included, else empty; `{{GUARD_NOTE}}` — " + destructive-command guard" if opted in, else empty). If `CLAUDE.md` lacks the `<!-- BEGIN init-agents -->`…`<!-- END init-agents -->` markers → append the block. If the markers exist → replace only the content between them. Create `CLAUDE.md` from the block if the file is missing.
5. **settings.local.json reminder**: keep machine-specific/personal permissions out of the shared file — mention `settings.local.json` (gitignored) for those.

## Phase 4 — Verify & report

1. Re-read every written file. Confirm each agent's YAML frontmatter parses and `name`s are unique; confirm `settings.json` is valid JSON (e.g. `jq . .claude/settings.json`); confirm `CLAUDE.md` has exactly one managed block.
2. Confirm hook scripts are executable (`ls -l .claude/hooks`).
3. Report to the user:
   - What was written (tree of new/updated files).
   - How to use it: `@explorer <q>`, `/feature <goal>`, `/fix <bug>`, `/review`, `/triage <bug-report>`; advanced: `claude --agent orchestrator`.
   - **Gotcha**: new subagent files load on **session restart** (or via `/agents`) — they won't be visible this session until then.
   - If anything is a `TODO:` (unknown commands), list it so the user fills it in.
   - One line: `git add .claude CLAUDE.md` when they're ready to share with the team.

## Uninstall

If `$ARGUMENTS` contains `uninstall`: remove `.claude/agents/{explorer,planner,implementer,reviewer,tester,orchestrator}.md`, `.claude/commands/{feature,fix,review,triage}.md`, `.claude/hooks/{format,guard}.sh`, the managed block between the `init-agents` markers in `CLAUDE.md`, and the hook matcher-groups in `.claude/settings.json` whose command contains `/.claude/hooks/` (leave the rest of settings untouched). Show the user exactly what you'll remove and confirm before deleting. Leave permissions you can't confidently attribute to this skill.

## Do NOT
- Never overwrite an existing `settings.json`, agent, or command file without showing a diff and asking — always merge or confirm.
- Never write outside `.claude/` and the single managed `CLAUDE.md` block.
- Never put secrets or machine-specific paths in the shared `settings.json`.
- Don't enable the blocking `guard.sh` by default — it affects every teammate.
- Don't invent build/test commands — if unknown, write `TODO:` and say so.
- Don't add agents the user didn't pick. Default to the **minimal** tier.

## Anti-patterns
- Generating all six agents on every repo "to be safe" → sprawl + flaky auto-delegation. Minimal by default.
- Encoding the formatter as `${file_path}` in the hook command — there is no such substitution; the wrapper reads stdin JSON with `jq`.
- Re-running and duplicating hook entries or stacking multiple `## Agent architecture` sections — always merge/replace the managed block.
- Reimplementing review/test logic the project already has — point the reviewer/tester at existing skills.
- Installing `/feature` or `/fix` while omitting the agents they name (minimal tier) without a fallback → dangling refs. The command templates degrade gracefully ("do it inline if the agent isn't installed"); preserve that when editing them.
