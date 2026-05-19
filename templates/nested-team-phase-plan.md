> **EXECUTION RULE**: This phase is pre-authorized by the approved master plan. Execute all steps without asking the user for confirmation between steps or at phase end. Stop only on: step failure, genuinely new decision, or user interrupt.

# Phase {{N}} Plan: {{phase-name}}

## Master Plan Reference
- File: {{master-plan-path}}  <!-- default: <cwd>/.plans/active/<master-slug>.md (legacy: ~/.claude/plans/active/<master-slug>.md) -->
- Phase tasks: {{N}}-1, {{N}}-2, ...

## Steps
- {{N}}-1: {{details}} [ ]
  - Implementer: Sonnet
  - Verification: {{test/build}}
- {{N}}-2: ...

## Review Checklist
- [ ] Alignment with design decisions
- [ ] Edge cases covered
- [ ] Security
- [ ] Test adequacy

## Completion
- [ ] All steps complete
- [ ] Review complete
- [ ] Master plan updated
