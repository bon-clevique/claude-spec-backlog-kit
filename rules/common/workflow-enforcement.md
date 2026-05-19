# Workflow Enforcement (rev. 2026-05-17 — existing-systems-first edition)

> This file holds **only Layer 2 (operational contract) text discipline**. Layer 1 (structural enforcement) is covered by hook / settings.json / skill / agent / template; Layer 3 (norms) is covered by CLAUDE.md. For detailed flow / state file specs / historical context see the Spec "Rebuilding c2 discipline as a minimal set anchored on existing systems" (Notion: https://www.notion.so/<YOUR-PAGE>).

## R-α: Spec approval only via the user's explicit utterance

c2 does not self-approve Spec/Plan content. Approval is recognized only when the user explicitly replies with phrases like 「承認」「OK」「進めて」. Phase 2 (Spec editing) inside the `/spec` skill does not advance to EnterPlanMode until receiving user OK (matches Stop Whitelist (1) external blocker).

**Rationale**: Spec / Plan is not irreversible, but this gate maintains the separation of responsibility for design decisions (the user owns the design decision; c2 owns execution). Self-approval by c2 breaks the downstream Mid-execution Judgment Rules (their precondition collapses).

## R-β: c2 dispatches autonomously; delegating judgment is prohibited

Mid-implementation decisions are auto-dispatched by c2 under the Mid-execution Judgment Rules (CLAUDE.md §Stop Whitelist & Mid-execution Judgment Rules). Three-choice presentation / multi-choice punt-back / 「どうしますか?」-style judgment-delegation is blocked by `confirmation-leak-detector.js` (cap 2 / session).

**Exceptions** (3 cases where stopping is allowed, the Stop Whitelist):
1. **External blocker**: technically not executable (Auth / payment / physical device / billing confirmation / built-in CLI command etc.)
2. **Plan-unwritten + irreversible**: force-push / DB drop / public release tag etc. with no plan entry
3. **the user explicit interrupt**: explicit interruption

Stopping outside these is an R-β violation.

## Discipline hierarchy (3-Layer model)

| Layer | Enforcement mechanism | Examples |
|---|---|---|
| **Layer 1: Structural** | hook / settings.json / skill / agent / template | plan-gate.js / confirmation-leak-detector.js / autoMode.hard_deny |
| **Layer 2: Operational contract** | This file's text discipline (R-α / R-β) | Spec approval only via the user's explicit utterance / c2 autonomous dispatch |
| **Layer 3: Norms** | CLAUDE.md (N-1〜N-4) | Goal end-to-end priority / existing-systems-first / 50+ lines → sub-agent / discipline-reduction candidate required |

Before introducing new discipline, evaluate in order Layer 1 → 2 → 3 (CLAUDE.md norm N-2 "existing-systems-first").

## Existing-systems-first principle

`~/.claude/` already contains the following existing systems. Before adding new discipline / hook / agent / skill, you must evaluate whether they cover the need:

- `settings.json` (hook configuration / autoMode.hard_deny / permissions / model / effortLevel)
- 25 existing hooks (`~/.claude/scripts/hooks/`)
- 18 existing skills (`~/.claude/skills/`)
- 12 existing agents (`~/.claude/agents/` — 16 agents after the discipline PR)
- templates (`~/.claude/templates/`)
- BACKLOG.md / CLAUDE.md / rules/common/*.md

New additions are warranted only when Layer 1 structural enforcement cannot substitute. List "at least 1 existing discipline that can be retired in its place" in Spec §13 Rule Reduction Candidates.

## Reference

- Mid-execution Judgment Rules SoT: `~/.claude/CLAUDE.md` §Stop Whitelist & Mid-execution Judgment Rules
- Backlog policy: `~/.claude/BACKLOG.md`
- Spec/Plan/Goal flow: Spec html (Notion DB "Claude Code Specs")
- Plan File Lifecycle: adopt the harness-provided path (`~/.claude/plans/<slug>.md`), under `.gitignore`
- Delivery: `~/.claude/rules/_lazy/delivery.md`
- Coding Standards: `~/.claude/rules/common/coding-standards.md`
- Learned Lessons: `~/.claude/rules/common/learned.md`

## Reduction history (2026-05-17)

The old workflow-enforcement.md (686 lines / ~65 discipline items) exceeded the cognitive-load threshold and degraded c2 quality (over-implementation proposals / YAGNI / mid-Phase stalls). After v1-v6 review in the Spec "Rebuilding c2 discipline as a minimal set anchored on existing systems", this file was compressed to Layer 2 text discipline (R-α / R-β) only.

What was reduced:
- ~15 machine-detectable text discipline items → migrated to Layer 1 (structural)
- ~20 items already structurally enforced by existing skill / agent / template → migrated to Layer 1
- ~8 items already SoT-managed in BACKLOG.md → duplicates removed
- ~12 items of old Plan Stack detail → covered by the Spec html / harness specification

Detailed historical context is preserved in `~/.claude/blog-source/2026-05-c2-discipline-redesign.md`.
