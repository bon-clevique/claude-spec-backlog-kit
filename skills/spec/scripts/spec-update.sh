#!/usr/bin/env bash
# spec-update.sh — Push edits in <toplevel>/docs/specs/<title>.md to the
# previously created Notion page (identified by ~/.claude/state/spec-page-<title>).
#
# Usage:
#   spec-update.sh "<title>"
#
# Errors exit non-zero with explanatory message to stderr.

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: spec-update.sh \"<title>\"" >&2
  exit 1
fi

TITLE="$1"

if [[ -z "$TITLE" ]]; then
  echo "Error: title is empty" >&2
  exit 1
fi

# Detect toplevel same way as spec-create.sh
TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -z "$TOPLEVEL" ]; then
  TOPLEVEL="$HOME/.claude"
fi

SPEC_FILE="$TOPLEVEL/docs/specs/$TITLE.md"
STATE_FILE="$HOME/.claude/state/spec-page-$TITLE"

if [ ! -f "$SPEC_FILE" ]; then
  echo "Error: md file not found: $SPEC_FILE" >&2
  exit 1
fi
if [ ! -f "$STATE_FILE" ]; then
  echo "Error: state file not found: $STATE_FILE" >&2
  echo "  Was this Spec created via spec-create.sh? (no page_id to update)" >&2
  exit 1
fi

PAGE_ID=$(cat "$STATE_FILE")
if [[ -z "$PAGE_ID" ]]; then
  echo "Error: state file is empty: $STATE_FILE" >&2
  exit 1
fi

RESULT=$(python3 "$HOME/.claude/skills/spec/scripts/md_to_notion.py" update \
  --md "$SPEC_FILE" \
  --page-id "$PAGE_ID")

PAGE_URL=$(echo "$RESULT" | python3 -c "import json,sys;print(json.load(sys.stdin)['url'])")

cat <<EOF
✓ Spec updated.

  md file : $SPEC_FILE
  Notion  : $PAGE_URL
EOF
