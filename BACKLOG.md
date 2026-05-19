# BACKLOG (v2 — Source of Truth)

> Spec for the cross-project task backlog. Skill: `~/.claude/skills/backlog/SKILL.md`. Implementation prose (rationale, sub-agent recipes, migration notes): `~/.claude/skills/backlog/implementation.md`. ADR: `~/.claude/adr/active/2026-05-10-002-backlog-v2-redesign.md`.

## 1. Layout

```
~/.claude/backlog/
├── <project-slug>/
│   ├── <ULID>-<slug>.md         # c2-assigned task
│   └── human-<ULID>-<slug>.md   # human-attention task (skipped by /backlog pick)
└── _archive/
    └── v1-scrapped/             # legacy v1 retired tasks (read-only, not scanned)
```

`<project-slug>` is derived from cwd via `~/.claude/scripts/lib/project-slug.sh`. Tasks raised outside any project root use `_global`.

## 2. Frontmatter schema (6 fields, EXACT)

```yaml
---
id: <26-char ULID>
slug: <kebab-case, ≤50 chars>
project: <slug or _global>
status: ready | doing | done
created: <ISO 8601 UTC>
updated: <ISO 8601 UTC>
---
```

**Disallowed**: `priority`, `assignee`, `attempts`, `depends_on`, `deps`, `parent`, `size`, `goal`, any v1 field. `frontmatter-set.sh` rejects them at write time. `status: blocked` and `status: cancelled` are no longer recognized.

## 3. Body schema (2 required + 2 optional sections at write time)

```markdown
# <Title from H1>

## Why                                  (REQUIRED at write time)
<Reason this task was queued — supplied at create time, never auto-extracted>

## How to resume                        (REQUIRED at write time)
<Concrete steps — file paths, line numbers, command names. No "TBD".>

## Done when                            (OPTIONAL at write time, REQUIRED at pick time)
<Verifiable closure criterion. Used by /backlog done as the inline log line.>

## Blocked by                           (OPTIONAL)
- <ULID-of-blocking-task>
- <ULID-of-blocking-task>
```

**Two-stage gate**:

- **Write-time** (`add-internal.sh`): `--why` and `--how-to-resume` are required and rejected if placeholder. `--done-when` is optional — auto-extracted tasks frequently lack it because the closure criterion isn't yet known when the upstream emitter writes the row.
- **Pick-time** (`/backlog pick`): all 3 sections (`## Why`, `## How to resume`, `## Done when`) must be present and non-placeholder. A task without `## Done when` is created in `status: ready` but pick gate skips it with a warning until the user edits the body.

**Placeholder set** (rejected at both stages where applicable): `TBD` / `tbd` / `TODO` / `todo` / `N/A` / `n/a` / `NA` / `na` / `-` / `—` (em-dash) / `?` / `auto-extracted*` (any string starting with `auto-extracted`) / empty / whitespace-only. The user must edit the file to fix.

A non-empty `## Blocked by` section makes the task waiting. `/backlog pick` skips it; `/backlog list` filters it out unless `--include-waiting`.

## 4. Lifecycle

```
                  (write — only via add-internal.sh)
                              │
                              ▼
                          ┌────────┐
                  ┌──────▶│ ready  │──────┐
                  │       └────────┘      │
                  │            │          │
                  │  /backlog  │  /backlog│
                  │  pick      │  pick    │
                  │            ▼          │
                  │       ┌────────┐      │
                  │       │ doing  │      │
                  │       └────────┘      │
                  │            │          │
                  │  /backlog  │          │
                  │  done      │          │
                  │            ▼          │
                  │  [BACKLOG-DONE] log   │
                  │  + rm file            │
                  └───────────────────────┘
```

There is no `done` directory. Closure is recorded in `~/.claude/activity.log` as `[BACKLOG-DONE] <ts> | id=… slug=… project=… | summary="<done-when>"`.

## 5. Pick gate (V1–V5 invariants)

The 5 invariants enforced by `/backlog pick` (and only by it — there is no separate `lint`):

- **V1**: `status ∈ {ready, doing, done}` (file existence implies ready or doing)
- **V2**: filename matches frontmatter `id` and `slug` exactly (with optional `human-` prefix)
- **V3**: 3 required body sections (`## Why`, `## How to resume`, `## Done when`) all present and non-placeholder
- **V4**: `human-` prefix tasks are never picked by `/backlog pick` (they need user action; surfaced via `/backlog list --human`)
- **V5**: a non-empty `## Blocked by` section masks the task from pick (warn-only at list time)

V3/V5 violations are warnings — the file is left in place. The user fixes the body or removes the file manually.

## 6. Auto-register (the only write path)

Tasks reach the backlog only via `add-internal.sh`, which is called by:

1. **PR merge hook** `~/.claude/scripts/hooks/plan-archive-on-merge.sh::import_backlog_section` (PostToolUse on `gh pr merge`) — parses the active plan file's `## 📋 Backlog 候補` markdown table. Required columns: `title | description | project-slug | defer-period`. One row → one `add-internal.sh` invocation. Logs `[PLAN-ARCHIVE-BACKLOG-IMPORT]` / `[PLAN-ARCHIVE-BACKLOG-SUMMARY]` to `~/.claude/activity.log`. Escape valves: `PLAN_ARCHIVE_BACKLOG_OFF=1` (skip entirely), `PLAN_ARCHIVE_BACKLOG_DRY_RUN=1` (log only). (Replaces the previous Stop-hook `backlog-auto-extractor.sh` removed in PR #40.)
2. **PostToolUse hook** `~/.claude/scripts/hooks/plan-out-of-scope-watcher.sh` — detects new bullets added to a plan file's `## Out of Scope` section. Records candidates in `~/.claude/state/oos-pending-<sid>.json`. The next-turn UserPromptSubmit reminder asks main to dispatch the `backlog-task-manager` sub-agent (`oos` mode).
3. **Mid-execution dispatch** — when main discovers an out-of-plan task (Backlog Discipline (a)+(b) check), it directly invokes `backlog-task-manager` (`midexec` mode) which validates and calls `add-internal.sh`.

**No `/backlog add` command**. Title/Why/How are always supplied by the upstream emitter. Completion-turn registration via Stop hook (the legacy `## 📋 Backlog 自動登録` table) is no longer supported — use Plan §📋 候補 or `backlog-task-manager (midexec)` instead.

## 7. Mid-execution Backlog Discipline (refresher)

When main encounters work that is not in the active plan, it must answer both:

- **(a) Independent of current goal?** — adding it would not bias resolution of the user's stated request
- **(b) Does not block the user's intent?** — current work can complete without it

Only when both are YES is the item allowed to be diverted to the backlog (sub-agent `midexec` mode). One YES + one NO → must extend the plan or escalate. Both NO → must complete inline. See `workflow-enforcement.md` §Mid-execution Judgment Rules.

## 8. Telemetry

Tags emitted to `~/.claude/activity.log` (single source: `~/.claude/scripts/backlog-log.sh emit_tag`):

- `[BACKLOG-WRITE]` — every successful `add-internal.sh` (via `atomic-write.sh`)
- `[BACKLOG-PICK]`  — `/backlog pick` claim
- `[BACKLOG-DONE]`  — `/backlog done` closure (carries the inline summary)
- `[PLAN-ARCHIVE-BACKLOG-IMPORT]` / `[PLAN-ARCHIVE-BACKLOG-SUMMARY]` — PR merge hook が plan §📋 から add-internal.sh 委譲で登録 (PR #40 で追加)
- `[PLAN-ARCHIVE-BACKLOG-SKIP]` — escape valve / add-internal-missing で skip
- `[PLAN-ARCHIVE-BACKLOG-SCHEMA-MISMATCH]` — plan §📋 table header が 4-column 期待形式 (`title | description | project-slug | defer-period`) と不一致
- `[PLAN-ARCHIVE-BACKLOG-MALFORMED]` / `[PLAN-ARCHIVE-BACKLOG-FAIL]` — 個別行の登録失敗

Aggregations are computed on demand via `grep` over `activity.log`. There is no `/backlog stats` and no separate health metrics script.

## 9. Cross-references

- Skill: `~/.claude/skills/backlog/SKILL.md`
- Commands: `~/.claude/skills/backlog/commands/{list,pick,done}.md`
- Sub-agent: `~/.claude/agents/backlog-task-manager.md`
- Implementation prose / migration notes: `~/.claude/skills/backlog/implementation.md`
- ADR: `~/.claude/adr/active/2026-05-10-002-backlog-v2-redesign.md`
- Workflow integration: `~/.claude/rules/common/workflow-enforcement.md` §Backlog 実行時のルール
