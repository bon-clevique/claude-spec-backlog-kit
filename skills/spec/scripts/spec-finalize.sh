#!/usr/bin/env bash
# spec-finalize.sh — After user OK, remove local md (Notion remains as SoT).
# State file (spec-page-<title>) is retained for Plan Mode integration
# (read by spec-update-pr.sh to attach Draft PR to Notion Spec page).
# State file is auto-cleaned at PR merge via plan-archive-on-merge.sh.
#
# Usage:
#   spec-finalize.sh "<title>"
#
# Errors exit non-zero with explanatory message to stderr.

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: spec-finalize.sh \"<title>\"" >&2
  exit 1
fi

TITLE="$1"

if [[ -z "$TITLE" ]]; then
  echo "Error: title is empty" >&2
  exit 1
fi

TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -z "$TOPLEVEL" ]; then
  TOPLEVEL="$HOME/.claude"
fi

SPEC_FILE="$TOPLEVEL/docs/specs/$TITLE.md"
STATE_DIR="$HOME/.claude/state"
STATE_FILE="$STATE_DIR/spec-page-$TITLE"
UNIQUE_ID_FILE="$STATE_DIR/spec-unique-id-$TITLE"

REMOVED=()
if [ -f "$SPEC_FILE" ]; then
  rm "$SPEC_FILE"
  REMOVED+=("$SPEC_FILE")
fi

# PR #41: symmetric cleanup — remove spec-unique-id-<title> alongside the md file.
# (spec-page-<title> is retained for Plan Mode integration; auto-cleaned at PR merge.)
if [ -f "$UNIQUE_ID_FILE" ]; then
  rm -f "$UNIQUE_ID_FILE"
  REMOVED+=("$UNIQUE_ID_FILE")
fi

if [ ${#REMOVED[@]} -eq 0 ]; then
  echo "Note: no md file to remove (already finalized or never created)." >&2
  if [ -f "$STATE_FILE" ]; then
    echo "  State file still present: $STATE_FILE" >&2
    echo "  (Will be auto-cleaned at PR merge via plan-archive-on-merge.sh)" >&2
  fi
  exit 0
fi

echo "✓ Spec finalized. Removed:"
for f in "${REMOVED[@]}"; do
  echo "  - $f"
done
echo ""
if [ -f "$STATE_FILE" ]; then
  echo "State file (Notion page_id reference) is retained for Plan Mode integration:"
  echo "  - $STATE_FILE"
  echo "  (Will be auto-cleaned at PR merge via plan-archive-on-merge.sh)"
  echo ""
fi
echo "Notion page (SoT) is retained. Continue with Plan Mode for implementation."
