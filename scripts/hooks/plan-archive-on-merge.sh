#!/usr/bin/env bash
# plan-archive-on-merge.sh
#
# PostToolUse hook (matcher: Bash). Detects successful `gh pr merge` invocations
# and deletes the active plan file. Disposition is rm-only — PR description serves
# as the permanent record in git history (plan §3.3, 2026-05-10).
#
# Trigger contract:
#   - Reads JSON from stdin (Claude Code PostToolUse contract)
#   - Inspects .tool_input.command for "gh pr merge"
#   - Inspects .tool_response.exit_code for success (0)
#
# Plan source policy:
#   Plan files live under ~/.claude/plans/<slug>.md (harness path).
#   Legacy <cwd>/.plans/active/ is scanned as fallback (read-only).
#
# Session ID resolution for state file cleanup:
#   Reads ~/.claude/state/plan-current-<sid> (written by plan-current-recorder.js)
#   to find the active plan path. Falls back to /tmp/plan-registry-<sid>/latest.path.
#   If sid cannot be resolved, state file cleanup is skipped (no-op, safe).
#
# Honors PLAN_ARCHIVE_DRY_RUN=1 — log only, no rm.

set -euo pipefail

PLANS_ROOT="${HOME}/.claude/plans"
STATE_DIR="${HOME}/.claude/state"
LOG="${HOME}/.claude/activity.log"

log() {
  printf '[%s] [plan-archive] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
}
log "entry: pid=$$ ppid=$PPID PLAN_ARCHIVE_DIAG=${PLAN_ARCHIVE_DIAG:-0}"

# Import §📋 Backlog 候補 markdown table rows into backlog DB.
# Delegates to ~/.claude/skills/backlog/scripts/add-internal.sh which enforces
# BACKLOG.md v2 schema (id/slug/project/status/created/updated frontmatter +
# H1 title + ## Why / ## How to resume / ## Done when body).
#
# Escape valve:
#   PLAN_ARCHIVE_BACKLOG_OFF=1  — disable entirely (log skip reason)
#   PLAN_ARCHIVE_BACKLOG_DRY_RUN=1 — call add-internal.sh --dry-run
#
# Failures are warning-only — never block plan rm.
import_backlog_section() {
  local plan_file="$1"
  if [ "${PLAN_ARCHIVE_BACKLOG_OFF:-0}" = "1" ]; then
    log "[PLAN-ARCHIVE-BACKLOG-SKIP] reason=PLAN_ARCHIVE_BACKLOG_OFF"
    return 0
  fi
  [ -f "$plan_file" ] || return 0

  local add_internal="$HOME/.claude/skills/backlog/scripts/add-internal.sh"
  if [ ! -x "$add_internal" ]; then
    log "[PLAN-ARCHIVE-BACKLOG-SKIP] reason=add-internal-missing path=$add_internal"
    return 0
  fi

  # Extract body of §📋 (between the header and the next H2 section).
  local section
  section=$(awk '/^## 📋 Backlog/{flag=1; next} flag && /^## /{flag=0} flag' "$plan_file" 2>/dev/null)
  [ -z "$section" ] && return 0

  # Validate header row: must have 4 columns titled title/description/project-slug/defer-period.
  local header
  header=$(echo "$section" | awk '/^\| / && !/^\|---/ { print; exit }')
  if ! echo "$header" | grep -qE '\| *title *\|.*description.*\|.*project.*\|.*defer'; then
    log "[PLAN-ARCHIVE-BACKLOG-SCHEMA-MISMATCH] expected 4-column header (title|description|project-slug|defer-period), got: $header"
    return 0
  fi

  local tmp
  tmp=$(mktemp)
  echo "$section" | awk '/^\| / && !/^\|---/ { print }' | tail -n +2 > "$tmp"

  local row_count=0
  local imported=0
  while IFS='|' read -r _ title desc project defer _; do
    row_count=$((row_count + 1))
    title=$(echo "$title" | sed -e 's/^ *//' -e 's/ *$//')
    desc=$(echo "$desc" | sed -e 's/^ *//' -e 's/ *$//')
    project=$(echo "$project" | sed -e 's/^ *//' -e 's/ *$//')
    defer=$(echo "$defer" | sed -e 's/^ *//' -e 's/ *$//')

    [ -z "$title" ] && continue
    [ "$title" = "(placeholder)" ] && continue
    [ -z "$desc" ] || [ "$desc" = "(placeholder)" ] && {
      log "[PLAN-ARCHIVE-BACKLOG-MALFORMED] row=$row_count reason=empty-description title=\"$title\""
      continue
    }

    # Sanitize project slug (defense-in-depth against path traversal).
    local scope="${project:-_claude-meta}"
    case "$scope" in
      *"/"*|*".."*|"") scope="_claude-meta" ;;
    esac
    scope=$(echo "$scope" | tr -cd 'a-zA-Z0-9_.-' | head -c 64)
    [ -z "$scope" ] && scope="_claude-meta"

    # Build how-to-resume with concrete pointer to source plan.
    local how_to_resume="Plan §📋 from $(basename "$plan_file") (PR merge import 2026-05-17 onwards). Defer: $defer."
    local done_when="Task completion criterion to be finalized at /backlog pick time."

    if [ "${PLAN_ARCHIVE_BACKLOG_DRY_RUN:-0}" = "1" ]; then
      local dry_path
      dry_path=$("$add_internal" \
        --title "$title" \
        --why "$desc" \
        --how-to-resume "$how_to_resume" \
        --done-when "$done_when" \
        --project "$scope" \
        --dry-run 2>&1) || {
          log "[PLAN-ARCHIVE-BACKLOG-DRY-FAIL] row=$row_count title=\"$title\" err=\"$dry_path\""
          continue
        }
      log "[PLAN-ARCHIVE-BACKLOG-DRY-RUN] $dry_path (title=\"$title\" scope=$scope defer=$defer)"
      imported=$((imported + 1))
    else
      local created_path
      created_path=$("$add_internal" \
        --title "$title" \
        --why "$desc" \
        --how-to-resume "$how_to_resume" \
        --done-when "$done_when" \
        --project "$scope" 2>&1) || {
          log "[PLAN-ARCHIVE-BACKLOG-FAIL] row=$row_count title=\"$title\" err=\"$created_path\""
          continue
        }
      log "[PLAN-ARCHIVE-BACKLOG-IMPORT] $created_path (scope=$scope defer=$defer)"
      imported=$((imported + 1))
    fi
  done < "$tmp"
  rm -f "$tmp" 2>/dev/null || true
  log "[PLAN-ARCHIVE-BACKLOG-SUMMARY] rows=$row_count imported=$imported"
}

# Read hook payload from stdin (best effort — never fail the tool call)
PAYLOAD="$(cat 2>/dev/null || true)"
[ -z "$PAYLOAD" ] && { log "skip: empty-payload"; exit 0; }

# Diagnostic mode: dump raw payload (with redaction) to ~/.claude/state/hook-debug-<sid>-<ts>.json
if [ "${PLAN_ARCHIVE_DIAG:-0}" = "1" ]; then
  # Prefer env var (v2.1.132+); fall back to stdin parse for legacy/test paths
  DIAG_SID="${CLAUDE_CODE_SESSION_ID:-}"
  if [ -z "$DIAG_SID" ] && command -v jq >/dev/null 2>&1; then
    DIAG_SID="$(printf '%s' "$PAYLOAD" | jq -r '.session_id // ""' 2>/dev/null || true)"
  fi
  DIAG_SID="${DIAG_SID:-unknown}"
  DIAG_TS="$(date +%s)"
  DIAG_FILE="${STATE_DIR}/hook-debug-${DIAG_SID}-${DIAG_TS}.json"
  mkdir -p "$STATE_DIR"
  # Multi-pattern redaction
  ( umask 077; printf '%s' "$PAYLOAD" | sed -E \
    -e 's/gh[ps]_[A-Za-z0-9_]{20,}/[REDACTED]/g' \
    -e 's/ghu_[A-Za-z0-9_]{20,}/[REDACTED]/g' \
    -e 's/gho_[A-Za-z0-9_]{20,}/[REDACTED]/g' \
    -e 's/ghr_[A-Za-z0-9_]{20,}/[REDACTED]/g' \
    -e 's/AKIA[0-9A-Z]{16}/[REDACTED]/g' \
    -e 's/sk-ant-[A-Za-z0-9_-]{20,}/[REDACTED]/g' \
    -e 's/xox[baprs]-[A-Za-z0-9-]+/[REDACTED]/g' \
    -e 's/Bearer [A-Za-z0-9_.-]+/Bearer [REDACTED]/g' \
    -e 's/"token"[[:space:]]*:[[:space:]]*"[^"]*"/"token":"[REDACTED]"/g' \
    -e 's/"authorization"[[:space:]]*:[[:space:]]*"[^"]*"/"authorization":"[REDACTED]"/gi' \
    -e 's/"api_key"[[:space:]]*:[[:space:]]*"[^"]*"/"api_key":"[REDACTED]"/g' \
    -e 's/"secret"[[:space:]]*:[[:space:]]*"[^"]*"/"secret":"[REDACTED]"/g' \
    -e 's/"password"[[:space:]]*:[[:space:]]*"[^"]*"/"password":"[REDACTED]"/g' \
    > "$DIAG_FILE" 2>/dev/null || true )
  log "DIAG: payload dumped to $(basename "$DIAG_FILE")"
  # Rotation: keep latest 10 files for this SID
  ls -t "${STATE_DIR}"/hook-debug-"${DIAG_SID}"-*.json 2>/dev/null | tail -n +11 | xargs -r rm 2>/dev/null || true
fi

# Extract command + exit_code; SID prefers env var (v2.1.132+) with stdin fallback for legacy/test
if command -v jq >/dev/null 2>&1; then
  CMD="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
  EXIT_CODE="$(printf '%s' "$PAYLOAD" | jq -r '.tool_response.exit_code // .response.exit_code // ""' 2>/dev/null || true)"
  SID="${CLAUDE_CODE_SESSION_ID:-$(printf '%s' "$PAYLOAD" | jq -r '.session_id // ""' 2>/dev/null || true)}"
else
  CMD="$(printf '%s' "$PAYLOAD" | grep -oE '"command":[[:space:]]*"[^"]*"' | head -1 | sed 's/^"command":[[:space:]]*"//; s/"$//')"
  EXIT_CODE="$(printf '%s' "$PAYLOAD" | grep -oE '"exit_code":[[:space:]]*[0-9]+' | head -1 | grep -oE '[0-9]+')"
  SID="${CLAUDE_CODE_SESSION_ID:-$(printf '%s' "$PAYLOAD" | grep -oE '"session_id":[[:space:]]*"[^"]*"' | head -1 | sed 's/^"session_id":[[:space:]]*"//; s/"$//')}"
fi

# Only act on `gh ... pr merge ...` (handles `gh pr merge`, `gh -R foo/bar pr merge`, etc.)
case "$CMD" in
  *"gh "*" pr merge"*) ;;       # gh -R repo pr merge / gh --repo=foo pr merge etc.
  *"gh pr merge"*) ;;           # 引数なし密接形 (現状互換)
  *) log "skip: cmd-mismatch (CMD=${CMD:0:80})"; exit 0 ;;
esac

# Only act on success (0 or empty/unknown — assume success if exit_code absent)
if [ -n "$EXIT_CODE" ] && [ "$EXIT_CODE" != "0" ]; then
  log "skip: exit-nonzero=$EXIT_CODE"
  exit 0
fi

# Find candidate active plans — prefer harness path (~/.claude/plans/),
# fall back to legacy harness active dir, then legacy cwd active dir.
shopt -s nullglob
candidates=()
SOURCE_TAG="harness-root"

if [ -d "$PLANS_ROOT" ]; then
  # Top-level *.md files under ~/.claude/plans/ (excluding active/, archived/ subdirs)
  for f in "$PLANS_ROOT"/*.md; do
    [ -e "$f" ] && candidates+=("$f")
  done
fi

# Legacy harness active dir fallback
PLANS_ACTIVE_DIR="${PLANS_ROOT}/active"
if [ "${#candidates[@]}" -eq 0 ] && [ -d "$PLANS_ACTIVE_DIR" ]; then
  candidates=("$PLANS_ACTIVE_DIR"/*.md)
  SOURCE_TAG="harness-active"
fi
shopt -u nullglob

if [ "${#candidates[@]}" -eq 0 ]; then
  log "skip: no-candidates"
  exit 0
fi

# Resolve which plan file to act on.
# If plan-current-<sid> is available, use it (deterministic path from recorder).
# With multiple candidates and no state, pick the single one or no-op.
PLAN_FILE=""

if [ -n "$SID" ]; then
  # Stack-aware plan-current resolution: prefer per-plan state, fall back to legacy
  STACK_FILE="${STATE_DIR}/plan-stack-${SID}"
  TOP_PID=""
  if [ -f "$STACK_FILE" ]; then
    TOP_PID=$(tail -1 "$STACK_FILE" 2>/dev/null | tr -d '\r\n')
  fi
  if [ -n "$TOP_PID" ] && [ -f "${STATE_DIR}/plan-current-${SID}-${TOP_PID}" ]; then
    STATE_CURRENT="${STATE_DIR}/plan-current-${SID}-${TOP_PID}"
  else
    STATE_CURRENT="${STATE_DIR}/plan-current-${SID}"
  fi
  if [ -f "$STATE_CURRENT" ]; then
    PLAN_FILE="$(cat "$STATE_CURRENT" 2>/dev/null | head -1 | tr -d '[:space:]')"
    # Verify the file still exists (may have been manually removed)
    if [ -n "$PLAN_FILE" ] && [ ! -f "$PLAN_FILE" ]; then
      log "skip: plan-current points to missing file $PLAN_FILE"
      PLAN_FILE=""
    fi
  fi
  # Fallback: /tmp/plan-registry-<sid>/latest.path
  if [ -z "$PLAN_FILE" ]; then
    REGISTRY_PATH="/tmp/plan-registry-${SID}/latest.path"
    if [ -f "$REGISTRY_PATH" ]; then
      PLAN_FILE="$(cat "$REGISTRY_PATH" 2>/dev/null | head -1 | tr -d '[:space:]')"
      if [ -n "$PLAN_FILE" ] && [ ! -f "$PLAN_FILE" ]; then
        PLAN_FILE=""
      fi
    fi
  fi
fi

# If no state-based resolution, fall back to single-candidate heuristic
if [ -z "$PLAN_FILE" ]; then
  if [ "${#candidates[@]}" -eq 1 ]; then
    PLAN_FILE="${candidates[0]}"
  else
    log "skip: multi-no-state count=${#candidates[@]} sid=${SID:-?}"
    exit 0
  fi
fi

SLUG="$(basename "$PLAN_FILE")"

# Dry-run mode
if [ "${PLAN_ARCHIVE_DRY_RUN:-0}" = "1" ]; then
  log "DRY-RUN: would rm $SLUG (src=$SOURCE_TAG sid=${SID:-?})"
  exit 0
fi

# Safety: containment check before rm
case "$PLAN_FILE" in
  "$PLANS_ROOT"/*) ;;
  *) log "skip: PLAN_FILE outside PLANS_ROOT: $PLAN_FILE"; exit 0 ;;
esac
case "$PLAN_FILE" in
  *"/.."*|*"/.."|".."/*)
    log "skip: PLAN_FILE contains traversal: $PLAN_FILE"; exit 0 ;;
esac
[ -L "$PLAN_FILE" ] && { log "skip: PLAN_FILE is a symlink: $PLAN_FILE"; exit 0; }
[ ! -f "$PLAN_FILE" ] && { log "skip: PLAN_FILE not a regular file: $PLAN_FILE"; exit 0; }

# Realpath normalization safety (macOS Tahoe で realpath 標準提供)
# Both PLAN_FILE and PLANS_ROOT are resolved to handle /var -> /private/var on macOS.
if command -v realpath >/dev/null 2>&1; then
  resolved=$(realpath "$PLAN_FILE" 2>/dev/null || echo "")
  resolved_root=$(realpath "$PLANS_ROOT" 2>/dev/null || echo "$PLANS_ROOT")
  if [ -n "$resolved" ]; then
    case "$resolved" in
      "$resolved_root"/*) ;;
      *)
        log "skip: realpath resolved outside PLANS_ROOT: $resolved"
        exit 0
        ;;
    esac
  fi
fi

# Pre-rm: set done flag first to minimize race window with Stop fallback
if [ -n "${SID:-}" ]; then
  ( umask 077; touch "${STATE_DIR}/plan-archive-done-${SID}" 2>/dev/null || true )
fi

# Extract Out of Scope bullets and stage as next-suggestion (Plan §3.2 + §6.3)
# Reads plan file BEFORE rm, writes to ~/.claude/state/next-suggestion-<sid>.md
if [ -n "${SID:-}" ] && [ -f "$PLAN_FILE" ]; then
  oos_content=$(awk '
    /^## .*Out of Scope/ { in_oos=1; next }
    /^## / && in_oos { exit }
    in_oos && /^- / { print }
  ' "$PLAN_FILE" 2>/dev/null || true)
  if [ -n "$oos_content" ]; then
    next_file="${STATE_DIR}/next-suggestion-${SID}.md"
    ( umask 077; cat > "$next_file" <<EOF
# Next-Session Suggestion (from merged plan)

The plan you just merged listed these items as Out of Scope. They may be candidates for follow-up work:

$oos_content

_Source plan: $(basename "$PLAN_FILE") (merged at $(date '+%Y-%m-%d %H:%M:%S'))_
_To dismiss, remove ~/.claude/state/next-suggestion-${SID}.md_
EOF
    ) || log "WARN: next-suggestion write failed"
    log "next-suggestion staged: $(basename "$next_file")"
  fi
fi

# §📋 Backlog 候補 section import (must run BEFORE rm — reads from plan file)
# Warning-only: failures never block plan rm.
import_backlog_section "$PLAN_FILE" || log "WARN: import_backlog_section non-zero exit (continuing)"

# Remove the plan file
if rm "$PLAN_FILE"; then
  log "deleted: $SLUG (src=$SOURCE_TAG sid=${SID:-?} — content preserved in PR)"
else
  log "ERROR: rm failed for $PLAN_FILE"
  exit 0
fi

# Spec html rm (new 2026-05-13, best-effort)
# 対応 spec は cwd git toplevel の docs/specs/<slug>.html。c2 session で cwd は固定でないため、
# 過去観測の project repo を limited list で scan する best-effort 方式
if [ -n "${PLAN_FILE:-}" ]; then
  PLAN_SLUG=$(basename "$PLAN_FILE" .md)
  SPEC_REMOVED=""
  # Common project repo paths (extend as needed)
  for project_root in "$HOME/dev"/*/; do
    spec_path="${project_root}docs/specs/${PLAN_SLUG}.html"
    if [ -f "$spec_path" ]; then
      rm -f "$spec_path" 2>/dev/null && SPEC_REMOVED="$spec_path"
      break
    fi
  done
  if [ -n "$SPEC_REMOVED" ]; then
    log "spec-rm: $SPEC_REMOVED"
  else
    log "spec-rm: no-file (slug=$PLAN_SLUG)"
  fi
fi

# Stack pop & per-plan state cleanup (new 2026-05-12)
# Resolve plan-id from the plan file path that was just rm'd, then:
#   1. unlink per-plan state files (plan-mode-active-<sid>-<plan-id> etc.)
#   2. remove the plan-id line from the session stack file
if [ -n "${PLAN_FILE:-}" ] && [ -n "${SID:-}" ]; then
  PLAN_ID=$(basename "$PLAN_FILE" .md)
  STACK_FILE="${STATE_DIR}/plan-stack-${SID}"

  # Unlink per-plan state files (best-effort)
  for state_name in plan-mode-active plan-current plan-approved; do
    rm -f "${STATE_DIR}/${state_name}-${SID}-${PLAN_ID}" 2>/dev/null || true
  done

  # Remove plan-id from stack (atomic write via tmp + rename)
  if [ -f "$STACK_FILE" ]; then
    tmp="${STACK_FILE}.tmp.$$"
    grep -vxF -- "$PLAN_ID" "$STACK_FILE" > "$tmp" 2>/dev/null || true
    if [ -s "$tmp" ]; then
      mv -f "$tmp" "$STACK_FILE" 2>/dev/null || rm -f "$tmp"
    else
      rm -f "$STACK_FILE" "$tmp" 2>/dev/null || true
    fi

    new_top=""
    [ -f "$STACK_FILE" ] && new_top=$(tail -1 "$STACK_FILE" 2>/dev/null | tr -d '\r\n')
    log "[PLAN-STACK-POP] sid=${SID} plan-id=${PLAN_ID} new_top=${new_top:-<empty>}"
  fi
fi

# Spec state file + Draft PR flag cleanup (new 2026-05-15 / Plan humming-strolling-conway §4.2)
# - draft-pr-created-<sid>: session-scoped, Draft PR 作成済 flag (spec-update-pr.sh が touch)
# - spec-page-<title>: Spec OK 後も保持していた state file。PR merge と同時に rm
#   spec title は plan slug と独立命名のため、最新 mtime の spec-page-* を rm 対象とする
#   (Spec/Plan 1:1 前提、複数 spec が並走する場合は false-positive のリスクあり)
if [ -n "${SID:-}" ]; then
  draft_pr_flag="${STATE_DIR}/draft-pr-created-${SID}"
  if [ -f "$draft_pr_flag" ]; then
    rm -f "$draft_pr_flag" && log "draft-pr-flag-rm: draft-pr-created-${SID}"
  fi
fi

# spec-page-* (most recent mtime)
SPEC_STATE_DIR="${STATE_DIR}"
if compgen -G "${SPEC_STATE_DIR}/spec-page-*" > /dev/null 2>&1; then
  spec_state=$(ls -t "${SPEC_STATE_DIR}"/spec-page-* 2>/dev/null | head -1 || true)
  if [ -n "$spec_state" ] && [ -f "$spec_state" ]; then
    rm -f "$spec_state" && log "spec-state-rm: $(basename "$spec_state")"
  fi
fi

# spec-unique-id-* も同 spec の状態として cleanup (PR #41 追加)
# Symmetric cleanup with spec-page-* — spec title derives both files
if compgen -G "${SPEC_STATE_DIR}/spec-unique-id-*" > /dev/null 2>&1; then
  uid_state=$(ls -t "${SPEC_STATE_DIR}"/spec-unique-id-* 2>/dev/null | head -1 || true)
  if [ -n "$uid_state" ] && [ -f "$uid_state" ]; then
    rm -f "$uid_state" && log "spec-uid-rm: $(basename "$uid_state")"
  fi
fi

# Clean up state files for this session
if [ -n "$SID" ]; then
  for state_key in "plan-approved-${SID}" "plan-current-${SID}" "plan-mode-active-${SID}"; do
    state_file="${STATE_DIR}/${state_key}"
    if [ -f "$state_file" ]; then
      rm "$state_file" && log "deleted state: $state_key" || log "WARN: rm failed for $state_key"
    fi
  done
fi

exit 0
