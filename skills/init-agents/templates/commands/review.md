---
description: Review the current diff for bugs, security issues, and regressions.
argument-hint: "[optional: path or scope]"
---

Dispatch the `reviewer` agent on the current change. If `$ARGUMENTS` is given, restrict the review to that path/scope; otherwise review the whole diff (`git diff` + `git diff --staged`).

If this project has dedicated review skills ({{REVIEW_SKILLS}}), prefer running those.

Return findings grouped **CRITICAL / WARNING / INFO** with `path:line` and concrete fixes. Do not apply changes unless I ask.
