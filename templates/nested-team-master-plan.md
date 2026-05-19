> ALL STEPS PRE-AUTHORIZED — All steps in the approved plan are pre-authorized. No per-step confirmation needed.

# Master Plan: {{project-name}}

## Overview
- Director: Main Conversation (Opus)
- Team Manager Model: Opus/Sonnet based on phase complexity
- Communication: Plan file + SendMessage (task-number based)
- Issues Dir: {{issues-dir}}

## Phase List
| Phase | Name | Manager Model | Dependencies | Status |
|-------|------|---------------|--------------|--------|
| 0 | ... | Sonnet | - | [ ] |
| 1 | ... | Opus | Phase 0 | [ ] |

## Phase N Tasks
- N-1: {{task}} [ ]
- N-2: {{task}} [ ]

## Issue Log
| ID | Phase | Summary | Status | File |
|----|-------|---------|--------|------|

## Delivery
> **Orchestrator/Director instruction**: Quote the steps below VERBATIM when delegating to Delivery Manager.
> Do NOT reconstruct from memory. Omitting merge or cleanup = silent scope reduction = plan violation.

- [ ] Pre-PR Checks (local CI + scope check + secret scan)
- [ ] Push & PR creation (--base main)
- [ ] Remote CI poll (Monitor + failure analysis if needed)
- [ ] Conflict resolution (if mergeable=CONFLICTING)
- [ ] Merge & Cleanup (squash merge + branch delete + git pull origin main)

## Final Review
- [ ] Director final verification
- [ ] Bug fixes (if found)
- [ ] Delivery: Local CI + scope check + secret scan → PR creation → remote CI → merge → /xcode-archive (iOS/Mac only; detection criteria in workflow-details.md) — execute end-to-end, no per-step confirmation
