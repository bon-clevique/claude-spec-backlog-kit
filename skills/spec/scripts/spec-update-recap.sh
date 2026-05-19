#!/usr/bin/env bash
# spec-update-recap.sh — Update Notion Spec page's `recap` (rich_text) property.
#
# Usage:
#   echo "<recap text>" | spec-update-recap.sh <page-id>
#
# Reads recap text from stdin (≤2000 chars after truncate). Page id can be UUID or 32hex.
# Env:
#   SPEC_RECAP_OFF=1     no-op + exit 0
#   NOTION_API_KEY       required (read by notion_wrapper.make_client)

set -euo pipefail

if [ "${SPEC_RECAP_OFF:-0}" = "1" ]; then
  echo "Note: SPEC_RECAP_OFF=1 set — skipping recap update" >&2
  exit 0
fi

if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
  echo "Usage: echo \"<recap text>\" | spec-update-recap.sh <page-id>" >&2
  exit 1
fi

PAGE_ID="$1"

# Read recap text from stdin (multi-line OK)
RECAP=$(cat -)

# Truncate to 2000 chars (with trailing "..." if over)
MAX_LEN=2000
if [ "${#RECAP}" -gt "$MAX_LEN" ]; then
  RECAP="${RECAP:0:$((MAX_LEN - 3))}..."
fi

python3 - "$PAGE_ID" "$RECAP" <<'PYEOF'
import os
import sys

sys.path.insert(0, os.path.expanduser("~/.claude/scripts/notion"))

from notion_wrapper import make_client, normalize_page_id, handle_api_error  # type: ignore
from notion_client.errors import APIResponseError, RequestTimeoutError  # type: ignore

raw_page_id, recap = sys.argv[1], sys.argv[2]
page_id = normalize_page_id(raw_page_id)

client = make_client()
try:
    client.pages.update(
        page_id=page_id,
        properties={
            "recap": {
                "rich_text": [
                    {
                        "type": "text",
                        "text": {"content": recap},
                        "annotations": {
                            "bold": False,
                            "italic": False,
                            "strikethrough": False,
                            "underline": False,
                            "code": False,
                            "color": "default",
                        },
                    }
                ]
            }
        },
    )
except (APIResponseError, RequestTimeoutError) as exc:
    handle_api_error(exc)

print(f"✓ recap updated for page {page_id}")
PYEOF
