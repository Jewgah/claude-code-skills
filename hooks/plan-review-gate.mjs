#!/usr/bin/env node
// plan-review-gate: PreToolUse hook on ExitPlanMode.
// Forces a review-plan pass before any plan is presented for approval.
// stateless - a sentinel in the plan text breaks the re-submit loop, no flag files.

let raw = "";
process.stdin.on("data", c => (raw += c));
process.stdin.on("end", () => {
  let plan = "";
  try { plan = (JSON.parse(raw).tool_input || {}).plan || ""; } catch {}

  // Already reviewed → let the plan through.
  if (plan.includes("plan-reviewed")) process.exit(0);

  // Who reviews: in a 10-plan trial on the author's own setup, a reviewer that never saw the
  // planning raised a bug-level finding the inline review had missed on 7 plans. Caveat: the plan
  // authors ran a cheaper model than the reviewer, so part of that gain may be the model and not
  // the fresh context. Small plans stay inline: a second agent per one-line fix is waste.
  const reason =
    "Auto plan-review gate: before presenting this plan, get THIS plan critiqued with the " +
    "review-plan skill: assumptions, blast radius, deploy safety, omissions. " +
    "WHO reviews: if the plan touches 3 or more files and you have the Agent tool, dispatch ONE " +
    "fresh reviewer, so the critique is not anchored on your own reasoning: Agent tool, " +
    "subagent_type general-purpose, model set to the strongest model you have, prompt \"cd " +
    "<repo>. Read-only: change no file. The user's request and stated constraints, word for " +
    "word: <paste them>. Invoke the /review-plan skill with the argument: review the plan file " +
    "at <plan file path>. Return the plan file's path and first heading, then the verdict " +
    "(Go / Adjust / Rethink) and every finding, verbatim.\" The plan file is the one THIS " +
    "session wrote, never the newest file in ~/.claude/plans (other sessions write there too); " +
    "with no plan file, paste the plan text verbatim instead. The user's request and " +
    "constraints go in as they were written, so the reviewer can judge the plan against what " +
    "was asked. Add nothing of your own: no summary of your reasoning, no hint at the expected " +
    "answer. When the report comes back, check that the path and heading it names are your " +
    "plan's before trusting the verdict. If, and only if, that fresh reviewer ran and returned " +
    "a verdict, add the line `<!-- double-checked: fresh reviewer, verdict Go -->` (with its " +
    "real verdict: Go, Adjust or Rethink) on its own line just above the final marker, so the " +
    "user can see the plan got a second opinion. Never add it after an inline review or a " +
    "failed dispatch. A smaller plan, no Agent tool, or a failed dispatch: invoke the skill " +
    "inline instead (Skill tool, name \"review-plan\"). " +
    "Revise the plan to incorporate the findings, then call " +
    "ExitPlanMode again with the revised plan and `<!-- plan-reviewed -->` as its final line. " +
    "Do this once. If the user already asked to skip the review, just append that marker line.";

  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: reason
    }
  }));
  process.exit(0);
});
