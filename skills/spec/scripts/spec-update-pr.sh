#!/usr/bin/env bash
# spec-update-pr.sh — Update Spec Notion page with 実装日 (now JST).
#
# Usage:
#   spec-update-pr.sh <spec-title> [<pr-url>] [<pr-number>]
#
# Note: <pr-url> and <pr-number> are accepted for caller compatibility
#       (create-draft-pr.sh) but NOT validated and NOT used internally — relation
#       update logic was removed in PR #41. Only <spec-title> is required.
#
# Behavior:
#   1. Resolve spec page_id from ~/.claude/state/spec-page-<spec-title>
#   2. Update Spec page property `実装日` (date) to now (ISO8601 + +09:00 JST).
#      `ステータス` is intentionally left untouched (Spec §3 Goal / DL-02:
#      GitHub-Notion sync handles status transitions).
#   3. On success, touch ~/.claude/state/draft-pr-created-$CLAUDE_SESSION_ID
#      (skipped with warning if CLAUDE_SESSION_ID is not set).
#
# Environment:
#   NOTION_API_KEY            — required
#   CLAUDE_SESSION_ID         — used to name the draft-pr-created marker; if
#                               unset, the marker is skipped with a warning

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: spec-update-pr.sh <spec-title> [<pr-url>] [<pr-number>]" >&2
  exit 1
fi

SPEC_TITLE="$1"
# PR_URL / PR_NUMBER are accepted for caller compatibility (create-draft-pr.sh)
# but no longer used internally — relation update logic was removed in PR #41
# (Notion GitHub-Notion sync handles linkage via the `closes <unique_id>` magic
# word; see ~/.claude/reference/notion-databases.md § "GitHub プルリクエスト (sync DB)").
PR_URL="${2:-}"
PR_NUMBER="${3:-}"

if [ -z "$SPEC_TITLE" ]; then
  echo "Error: spec-title is required" >&2
  exit 1
fi

STATE_FILE="$HOME/.claude/state/spec-page-$SPEC_TITLE"
if [ ! -f "$STATE_FILE" ]; then
  echo "Error: spec page state file not found: $STATE_FILE" >&2
  echo "  Run /spec first to create the Notion page, or check the title spelling." >&2
  exit 1
fi

SPEC_PAGE_ID=$(head -1 "$STATE_FILE" | tr -d '[:space:]')
if [ -z "$SPEC_PAGE_ID" ]; then
  echo "Error: spec page state file is empty: $STATE_FILE" >&2
  exit 1
fi

NOW_JST=$(date '+%Y-%m-%dT%H:%M:%S+09:00')

# Step 1: update 実装日 (always required) ----------------------------------
python3 - "$SPEC_PAGE_ID" "$NOW_JST" <<'PYEOF'
import os
import sys

# Heredoc execution makes __file__ == "<stdin>", so a relative sys.path insert
# is meaningless. Use the absolute path only.
sys.path.insert(0, os.path.expanduser("~/.claude/scripts/notion"))

from notion_wrapper import make_client, handle_api_error  # type: ignore
from notion_client.errors import APIResponseError, RequestTimeoutError  # type: ignore

page_id, now_jst = sys.argv[1], sys.argv[2]
client = make_client()
try:
    client.pages.update(
        page_id=page_id,
        properties={"実装日": {"date": {"start": now_jst}}},
    )
except (APIResponseError, RequestTimeoutError) as exc:
    handle_api_error(exc)
print(f"✓ updated 実装日 = {now_jst}", file=sys.stderr)
PYEOF

# Step 2: marker file for completion-gate -------------------------------------
# 実装日 update (Step 1) succeeded by this point, which is the gate condition
# we need to signal to completion-gate.js.
SID="${CLAUDE_SESSION_ID:-}"
if [ -z "$SID" ]; then
  echo "Warning: CLAUDE_SESSION_ID not set — skipping draft-pr-created marker" >&2
else
  MARKER="$HOME/.claude/state/draft-pr-created-$SID"
  mkdir -p "$(dirname "$MARKER")"
  # umask 077 → marker is user-only readable (0600). Subshell scopes the umask
  # so the surrounding shell's umask is unaffected.
  ( umask 077; : > "$MARKER" )
  echo "✓ marker created: $MARKER" >&2
fi

echo "✓ spec-update-pr.sh complete (実装日 updated; marker set)"
