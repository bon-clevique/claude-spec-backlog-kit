#!/usr/bin/env bash
# create-draft-pr.sh — One-shot Draft PR bootstrapper invoked immediately after
# Plan approval. Designed to satisfy workflow-enforcement.md §Plan 承認直後の
# 即実行ルール: Main session can fire a single tool call to create the branch,
# the empty commit, push, the Draft PR, and update the Spec Notion page.
#
# Usage:
#   create-draft-pr.sh <plan-file-path>
#
# Behavior (all in one shell):
#   1. Derive SLUG from the plan-file basename (strip .md).
#   2. BRANCH = $(branch-from-plan.sh "$SLUG.md") → "feature/<tail>".
#   3. Resolve target git repo via plan-pr-target-resolver.sh:
#        - case-b: cwd is the git toplevel → operate in cwd
#        - case-a: cwd non-git, single git target → cd into that target
#        - other : abort (cannot create a PR)
#   4. git checkout -b "$BRANCH" (or `git checkout` if it already exists).
#   5. git commit --allow-empty -m "chore: prepare draft PR for $SLUG"
#   6. git push -u origin "$BRANCH"
#   7. Generate PR body via plan-pr-body-dispatch.sh into /tmp/pr-body-<sanitized>.md
#   8. gh pr create --draft --base main → capture PR_URL & PR_NUMBER.
#   9. Best-effort: pick the most-recent ~/.claude/state/spec-page-* state file
#      and call spec-update-pr.sh with its title, the PR_URL, and the PR_NUMBER.
#      If no spec page state file exists, log a warning and skip (Plan slug and
#      Spec title are independently named so a fallback heuristic is required).
#  10. Print PR_URL on stdout. Everything else goes to stderr.
#
# Environment:
#   DRAFT_PR_AUTO_OFF=1 — exit 0 immediately without touching git/gh/Notion
#                         (Spec §9.2 rollback path)
#   CLAUDE_SESSION_ID   — forwarded to spec-update-pr.sh for the marker file

set -euo pipefail

if [ "${DRAFT_PR_AUTO_OFF:-0}" = "1" ]; then
  echo "Note: DRAFT_PR_AUTO_OFF=1 — skipping Draft PR creation" >&2
  exit 0
fi

if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
  echo "Usage: create-draft-pr.sh <plan-file-path>" >&2
  exit 1
fi

PLAN_FILE="$1"
if [ ! -f "$PLAN_FILE" ]; then
  echo "Error: plan file not found: $PLAN_FILE" >&2
  exit 1
fi

CLAUDE_HOME="$HOME/.claude"
LIB_DIR="$CLAUDE_HOME/scripts/lib"
SCRIPTS_DIR="$CLAUDE_HOME/scripts"
STATE_DIR="$HOME/.claude/state"
ACTIVITY_LOG="$HOME/.claude/activity.log"

log_magic_word() {
  # $1 = tag (e.g., "MAGIC-WORD-OK"), $2 = optional detail
  local ts
  ts=$(date '+%Y-%m-%dT%H:%M:%S+09:00')
  printf '[%s] [%s] %s\n' "$ts" "$1" "${2:-}" >> "$ACTIVITY_LOG" 2>/dev/null || true
}

# Resolve most-recent spec page state file once (single source of truth — TOCTOU safe)
RECENT_SPEC_STATE_FILE=$(ls -t "$STATE_DIR"/spec-page-* 2>/dev/null | head -1 || true)

PLAN_BASENAME=$(basename "$PLAN_FILE")
SLUG="${PLAN_BASENAME%.md}"

# 2. Derive branch name --------------------------------------------------------
BRANCH=$(bash "$LIB_DIR/branch-from-plan.sh" "$SLUG.md")
if [ -z "$BRANCH" ]; then
  echo "Error: failed to derive branch name from slug: $SLUG" >&2
  exit 1
fi

# 3. Resolve target git repo ---------------------------------------------------
# shellcheck disable=SC1091
source "$LIB_DIR/plan-pr-target-resolver.sh"

# Without explicit changed-files args the resolver returns case-b if cwd is a
# git toplevel, otherwise case-c. Pass the plan file as a hint so case-a
# resolution kicks in when the plan file lives inside a git repo (e.g. when
# editing files under ~/.claude from a non-git cwd).
RESOLVE_OUT=$(resolve_pr_target_repo "$PLAN_FILE" "$CLAUDE_HOME")
CASE_TAG=$(printf '%s\n' "$RESOLVE_OUT" | awk '{print $1}')
TARGET_REPO=$(printf '%s\n' "$RESOLVE_OUT" | awk '{print $2}')

case "$CASE_TAG" in
  case-b)
    : # operate in cwd
    ;;
  case-a)
    if [ -z "$TARGET_REPO" ]; then
      echo "Error: case-a resolved but TARGET_REPO empty" >&2
      exit 1
    fi
    echo "Note: case-a — switching to target repo: $TARGET_REPO" >&2
    cd "$TARGET_REPO"
    ;;
  *)
    echo "Error: cannot resolve PR target repo (resolver said: $RESOLVE_OUT)" >&2
    echo "  cwd: $PWD" >&2
    exit 1
    ;;
esac

# 4. Branch checkout (create if absent) ---------------------------------------
if git rev-parse --verify --quiet "$BRANCH" >/dev/null; then
  echo "Note: branch already exists, checking out: $BRANCH" >&2
  git checkout "$BRANCH"
else
  git checkout -b "$BRANCH"
fi

# 5. Empty commit (idempotent — skip if our marker commit already exists on the
#    branch ahead of origin) ---------------------------------------------------
# Title prefix heuristic: SLUG cannot reliably encode commit-type, so default
# to "feat:" prefix. Strip the "feature/" prefix from BRANCH so the commit /
# PR title carry the human-readable tail (no UUID slug noise).
PR_TITLE_TAIL="${BRANCH#feature/}"
COMMIT_MSG="chore: prepare draft PR for $PR_TITLE_TAIL"

if git log --oneline "origin/$BRANCH..HEAD" 2>/dev/null | grep -qF "$COMMIT_MSG"; then
  echo "Note: empty commit already present on $BRANCH — skipping" >&2
else
  git commit --allow-empty -m "$COMMIT_MSG"
fi

# 6. Push ----------------------------------------------------------------------
git push -u origin "$BRANCH"

# 7. PR body via dispatcher (plan-aware) --------------------------------------
SAFE_BRANCH="${BRANCH//\//_}"
PR_BODY_FILE="/tmp/pr-body-${SAFE_BRANCH}.md"
bash "$SCRIPTS_DIR/plan-pr-body-dispatch.sh" "$BRANCH" main > "$PR_BODY_FILE"

# 7.5. magic word 自動挿入 (Notion 公式 GitHub-Notion sync 連携のため) --------
if [ "${SPEC_MAGIC_WORD_OFF:-0}" = "1" ]; then
  echo "Note: SPEC_MAGIC_WORD_OFF=1 — skipping magic word injection" >&2
  log_magic_word "MAGIC-WORD-SKIP" "reason=env-off"
elif [ -n "$RECENT_SPEC_STATE_FILE" ]; then
  STATE_BASENAME=$(basename "$RECENT_SPEC_STATE_FILE")
  SPEC_TITLE="${STATE_BASENAME#spec-page-}"
  UNIQUE_ID_FILE="$STATE_DIR/spec-unique-id-$SPEC_TITLE"
  UNIQUE_ID_VAL=""

  if [ -s "$UNIQUE_ID_FILE" ]; then
    UNIQUE_ID_VAL=$(head -1 "$UNIQUE_ID_FILE" | tr -d '[:space:]')
  else
    # Fallback: spec-page-<title> から page_id を読み、Notion API pages.retrieve で unique_id 取得 + backfill
    SPEC_PAGE_ID=$(head -1 "$RECENT_SPEC_STATE_FILE" | tr -d '[:space:]')
    if [ -n "$SPEC_PAGE_ID" ]; then
      UNIQUE_ID_VAL=$(python3 - "$SPEC_PAGE_ID" <<'PYEOF' || true
import os, sys
sys.path.insert(0, os.path.expanduser("~/.claude/scripts/notion"))
try:
    from notion_wrapper import make_client
    client = make_client()
    page = client.pages.retrieve(page_id=sys.argv[1])
    uid = page.get("properties", {}).get("ID", {}).get("unique_id", {})
    prefix = uid.get("prefix", "")
    number = uid.get("number")
    if prefix and number is not None:
        print(f"{prefix}-{number}")
except Exception as e:
    print(f"[MAGIC-WORD-API-FAIL] {e}", file=sys.stderr)
PYEOF
)
      if [ -n "$UNIQUE_ID_VAL" ]; then
        echo "$UNIQUE_ID_VAL" > "$UNIQUE_ID_FILE"
        echo "Note: unique_id backfilled to $UNIQUE_ID_FILE" >&2
        log_magic_word "MAGIC-WORD-BACKFILL" "$UNIQUE_ID_VAL"
      fi
    fi
  fi

  if [ -n "$UNIQUE_ID_VAL" ]; then
    # PR body 先頭に "closes <unique_id>\n\n" を prepend
    { echo "closes $UNIQUE_ID_VAL"; echo; cat "$PR_BODY_FILE"; } > "$PR_BODY_FILE.tmp" \
      && mv "$PR_BODY_FILE.tmp" "$PR_BODY_FILE"
    echo "Note: prepended 'closes $UNIQUE_ID_VAL' to PR body for Notion GitHub-Notion sync" >&2
    log_magic_word "MAGIC-WORD-OK" "prefix=$UNIQUE_ID_VAL title=$SPEC_TITLE"
  else
    echo "Warning: spec unique_id resolution failed; PR body will lack 'closes <unique_id>' magic word" >&2
    log_magic_word "MAGIC-WORD-FAIL" "spec_title=$SPEC_TITLE"
  fi
fi

# 8. gh pr create (idempotent — reuse existing OPEN PR if present) -----------
PR_TITLE="feat: $PR_TITLE_TAIL"

EXISTING_PR=$(gh pr list --head "$BRANCH" --state open --json url --jq '.[0].url' 2>/dev/null || true)
if [ -n "$EXISTING_PR" ]; then
  echo "Note: Draft PR already exists for $BRANCH: $EXISTING_PR" >&2
  PR_URL="$EXISTING_PR"
  # PR #41 Fix: push the magic-word-prepended body to the existing PR so re-runs
  # don't silently lose the `closes <unique_id>` prefix.
  PR_NUMBER_FROM_URL=$(echo "$PR_URL" | grep -oE '[0-9]+$')
  if [ -n "$PR_NUMBER_FROM_URL" ] && [ -f "$PR_BODY_FILE" ]; then
    gh pr edit "$PR_NUMBER_FROM_URL" --body-file "$PR_BODY_FILE" >/dev/null 2>&1 || \
      echo "Warning: gh pr edit failed for existing PR $PR_NUMBER_FROM_URL" >&2
  fi
else
  PR_URL=$(gh pr create \
    --draft \
    --base main \
    --title "$PR_TITLE" \
    --body-file "$PR_BODY_FILE")
fi

if [ -z "$PR_URL" ]; then
  echo "Error: gh pr create did not return a URL" >&2
  exit 1
fi

PR_NUMBER=$(gh pr view --json number --jq '.number')
if [ -z "$PR_NUMBER" ]; then
  echo "Error: failed to read PR number via gh pr view" >&2
  exit 1
fi

echo "✓ Draft PR created: $PR_URL (#$PR_NUMBER)" >&2

# 9. Spec page update (best-effort, fallback heuristic) ----------------------
# Plan slug ↔ Spec title are independently named, so we use the most-recent
# ~/.claude/state/spec-page-* state file by mtime as the best-effort match.
# RECENT_SPEC_STATE_FILE was resolved once at the top of the script (TOCTOU safe).
if [ -z "$RECENT_SPEC_STATE_FILE" ]; then
  echo "Warning: no spec page state found, skipping spec update" >&2
else
  # Strip leading "spec-page-" → derive Spec title
  STATE_BASENAME=$(basename "$RECENT_SPEC_STATE_FILE")
  SPEC_TITLE="${STATE_BASENAME#spec-page-}"
  echo "Note: using spec page state file: $RECENT_SPEC_STATE_FILE (title: $SPEC_TITLE)" >&2
  if ! bash "$CLAUDE_HOME/skills/spec/scripts/spec-update-pr.sh" \
        "$SPEC_TITLE" "$PR_URL" "$PR_NUMBER"; then
    echo "Warning: spec-update-pr.sh failed (non-fatal)" >&2
  fi
fi

# 10. Primary output: PR URL on stdout ----------------------------------------
printf '%s\n' "$PR_URL"
