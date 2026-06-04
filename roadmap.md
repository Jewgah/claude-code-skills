# Roadmap — claude-code-skills

## Existing Features

- [x] `/review-deep` — deep multi-agent code review (4 parallel reviewers + adversarial skeptic verification, diff-sized fan-out)
- [x] `/review-plan` — pre-implementation plan review (assumptions, failure paths, blast radius, devil's advocate, Go/Adjust/Rethink verdict)
- [x] `/init-agents` — agent-team scaffolder (stack detection, agents/commands/hooks templates, minimal/full tiers, uninstall)
- [x] `install.sh` — one-shot installer (idempotent, skips existing)
- [x] README with install + usage instructions
- [x] MIT license

## Planned

- [ ] Additional generic skills from the private collection (candidates: `/sessions`, `/skill-stats`, `/create-skill`, `/security-audit`, `/diagnose`, `/guard`)
- [ ] Screenshots / sample review output in README

## Changelog

### 2026-06-04 — /init-agents + installer (8406533 → this commit)
- Ported `/init-agents` skill (15 files: 6 agent templates, 4 pipeline commands, 2 hooks, settings partial) — verified clean of private references
- Added `install.sh` (tested fresh + idempotent re-run in sandboxed HOME)
- README: init-agents section, install-script instructions
- GitHub topics added for discoverability

### 2026-06-04 — Initial release (8406533)
- Imported sanitized `/review-deep` (skill) and `/review-plan` (slash command) from private collection
- Added README, MIT license, roadmap
