# MANDATORY FIRST ACTION

> **MANDATORY FIRST ACTION**: Read `~/.claude/rules/_lazy/delivery.md` before any other tool call.
> This is the canonical delivery rules. Do not proceed without loading it.
> The plan's `## Delivery` section (quoted verbatim in this prompt) supplements but does not replace those rules.

# Delivery Manager Prompt Template

Boilerplate for delegating to the Delivery Manager sub-agent. Added 2026-05-17.

Right before standing up the Delivery Manager sub-agent, Main (Orchestrator) must re-Read the plan file and verbatim-attach the full `## 10. Delivery` section + the boilerplate below to the prompt (no memory / summaries, see L-026):

```
You are the Delivery Manager. Complete delivery of this PR using the procedure below:

<plan §10 verbatim copy>

Additionally, strictly observe:
- Verbatim-attach each of the 7 reviewers' (security/architect/code/pdm/ceo/ops/dx) markdown output and append to the PR body
- Each finding must be preceded by a checkbox `[ ]` and have a handling-status column
- Unresolved findings: (a) if out of scope for this PR, list in Plan §📋 or Spec §10 OoS; (b) if a miss, fix within this PR
- PR body adopts the structure of ~/.claude/templates/pull-request-template.md
- If the delegated party launches further sub-agents, the Delivery Manager passes the same prompt along
```
