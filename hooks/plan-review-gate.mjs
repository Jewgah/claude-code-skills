#!/usr/bin/env node
// plan-review-gate: PreToolUse hook on ExitPlanMode.
// Forces a review-plan pass before any plan is presented for approval.
// ponytail: stateless — a sentinel in the plan text breaks the re-submit loop, no flag files.

let raw = "";
process.stdin.on("data", c => (raw += c));
process.stdin.on("end", () => {
  let plan = "";
  try { plan = (JSON.parse(raw).tool_input || {}).plan || ""; } catch {}

  // Already reviewed → let the plan through.
  if (plan.includes("plan-reviewed")) process.exit(0);

  const reason =
    "Auto plan-review gate: before presenting this plan, invoke the review-plan skill " +
    "(Skill tool, name \"review-plan\") to critique THIS plan — assumptions, blast radius, " +
    "deploy safety, omissions. Revise the plan to incorporate its findings, then call " +
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
