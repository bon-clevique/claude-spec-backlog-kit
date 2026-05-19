# CLAUDE.md — Bon's Dev Environment (Global)

> **This file is an index**. Rule bodies live in separate files (SoT = Single Source of Truth).
> - **Workflow discipline / Stop Whitelist / Mid-execution Judgment / Devil's Advocate / End-to-End Verification / Permission vs Workflow** → `rules/common/workflow-enforcement.md` (auto-loaded)
> - **Backlog v2 policy (6-field schema / 3 status values / 3-section body gate / auto-register)** → `~/.claude/BACKLOG.md`
> - **Coding Standards** → `rules/common/coding-standards.md` (auto-loaded)
> - **Delivery rules** → `~/.claude/rules/_lazy/delivery.md` (lazy-loaded via `/spec` skill instruction or Delivery Manager template; not auto-loaded)
> - **Lessons learned** → `rules/common/learned.md` (auto-loaded)

## Default Permissive Workflow (Plan When User Opts In)
Details → `~/.claude/reference/default-permissive-workflow.md` (Edit/Write default permitted; full plan flow only when user opts into Plan Mode; Stop Whitelist 3 cases in workflow-enforcement.md)

## First Response
- **Timestamp**: `🕐 YYYY-MM-DD HH:MM JST` via `date '+%Y-%m-%d %H:%M'` (system is JST)
- Chain with another command when possible

## Communication
- **Processing**: English for tool calls, code, internal reasoning
- **Completion reports**: Japanese for all reports, summaries, and status updates

## System
- **OS**: macOS Tahoe 26.2 | **Terminal**: Kitty (UDEV Gothic NFLG 14pt) | **Editor**: Xcode
- **Language**: Japanese/English bilingual | **Apple Developer Program**: Active

## Key Paths

| Path | Purpose |
|---|---|
| `~/dev/` | All dev projects |
| `~/.claude/skills/` | Claude Code skills |
| `~/.claude/adr/active/` | ADR (lessons learned) |
| `~/.claude/actions/` | Action items (template: `~/.claude/templates/action-default.md`) |
| `~/.claude/reference/` | Reference docs |
| `~/.claude/scripts/` | Scripts |
| `~/.claude/BACKLOG.md` | Backlog v2 policy (6-field schema / 3 status values / 3-section body gate) |
| `~/.claude/backlog/<project-slug>/` | Cross-project backlog location (`<ulid>-<slug>.md`) |
| `~/.claude/activity.log` | Activity log (auto-recorded by Stop hook) |

## Environment
- **Runtimes**: All via `asdf` (Homebrew prohibited). `.tool-versions` at project root
- **Env vars**: `.env`, `UPPER_SNAKE_CASE`, must be in `.gitignore`
- **Notion**: API v2026-03-11 (`data_source_id`). DB ref: `~/.claude/reference/notion-databases.md`. API key in `.zshenv` as `NOTION_API_KEY`
- **Sandbox Apple ID**: `<your-org>.mail+000@gmail.com` (App Store Connect Sandbox Tester)

## Constraints
- **File access**: Claude.ai operates only under `~/dev/`
- Out-of-scope tasks: explain reason and alternatives first

## AI Role Delegation
Details → `~/.claude/reference/ai-role-delegation.md` (Opus main orchestrator xhigh; design/DA/security sub-agents effort high; full agent roster + auto-triggers)

## Agent Teams
- **Required**: Plan-scale work → agent teams. Main = orchestrator; delegate Edit/Write to sub-agents
- **Skippable**: Questions only / single file ≤20 lines
- **Named agents**: Always set `name` param. Reuse via `SendMessage(to: name)`. Nested teams (3+ phases) → `~/.claude/templates/nested-team-*.md`
- **`@`-mention typeahead** (v2.1.122+): `@<name>` enables typeahead invocation

## Batch Processing
Use `/batch` when: uniform repetitive changes (no design decisions) + 5+ files + independent units.

## Git
- No direct push to main. Feature branch + PR. Always branch from `origin/main`. No squash-merged branch reuse
- Branches: `feature/`, `fix/`, `refactor/`, `docs/` | Commits: `feat`, `fix`, `test`, `refactor`, `docs`, `chore`
- Merge: Squash and Merge → delete branch. Details → `~/.claude/reference/git-workflow.md`

## Workflow Details
- **Research & Reuse**: Search existing solutions before implementing. OSS 80%+ → prefer it
- **Code Review** [Required]: Plan-scale → delegate the 3-perspective team (security + code + architect) to sub-agents inside the plan. No plan → code-reviewer alone. `/ultrareview` is default skip (see ADR `2026-05-07-001`)
- **ADR**: Triggers → `~/.claude/reference/adr-triggers.md` | Template → `~/.claude/adr/template.md`
- **Doc System**: 4-layer model → `~/.claude/reference/doc-system.md`
- **Feedback Loop**: Rules → `~/.claude/reference/feedback-loop.md` | Promotion → `~/.claude/scripts/promote-lessons.sh`
- **Plan File Hooks**: `plan-current-recorder.js` (PostToolUse on Write) | `plan-enforce.js` (PreToolUse sub-agent enforcement) | `plan-approval-marker.js` | `plan-archive-on-merge.sh` (details → workflow-enforcement.md §Plan File Lifecycle Protocol / §Sub-agent enforcement)
- **Pre-Completion**: No completion without working proof
- **Recurring tasks**: `/loop` (same-session cron) | `/schedule` (cross-session routine) | `/plan-done` (archive a non-git project's plan to `~/.claude/plans/archived/`)

## Performance
Details → `~/.claude/reference/c2-performance.md`

## Project-Level Hooks
- **JS/TS auto-format + typecheck**: Copy `~/.claude/templates/settings.jsts.json` to `<project>/.claude/settings.local.json`
- Hook types & scripts → `~/.claude/reference/`

## Skills
`@backlog` v2 (3 commands: list / pick / done — auto-register via Stop hook + sub-agent) | `@setup-project` | `@ship` (integrated delivery) | `@xcode-archive` (TestFlight) | `@start-simulator` | `@notion-add-note` | `@create-test-db` | `@task-runner` | `@react-best-practices` | `@web-design-guidelines` | `@estimate-impact` | `@release-notes`

## Context Compaction
- **PostCompact hook**: `post-compact-context.sh` auto-recovers active plan file path and modified files list. Approval status must be verified by reading the plan file
- Additionally preserve: test results, architectural decisions, current delivery phase progress

## User Action Auto-Save
When generating content requiring user confirmation/execution/decision: auto-save to `~/.claude/actions/` per template. Filename: `YYYY-MM-DD-NNN.md`. Delete on completion.

## Autonomous-Run KPI
Details → `~/.claude/reference/autonomous-run-kpi.md`

## c2 Norms
Details → `~/.claude/reference/c2-norms.md` (N-1 Goal end-to-end / N-2 existing-systems-first / N-3 50-line sub-agent delegation / N-4 rule reduction candidates)

## Delivery delegation prompt template
Details → `~/.claude/templates/delivery-manager-prompt.md`

## /compact auto-execution norm
Details → `~/.claude/reference/compact-execution-norm.md`
