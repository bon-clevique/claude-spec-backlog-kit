#!/usr/bin/env bash
# spec-create.sh — Create docs/specs/<title>.md from template at cwd git toplevel,
# then upload to the Notion spec DB ("Claude Code Specs") and record page_id.
#
# Usage:
#   spec-create.sh "<title (日本語可)>" [--skip-upload]
#
# Behavior:
#   1. Validate title (no newlines, no leading/trailing space, no "/" or null)
#   2. Detect git toplevel (fallback to ~/.claude if cwd is non-git)
#   3. If md file doesn't exist: copy spec-default.md → <toplevel>/docs/specs/<title>.md
#      If it already exists: use the existing file (allows the c2-friendly flow:
#      template-copy → section-fill → spec-create.sh for upload)
#   4. If --skip-upload is given: stop here (just create the md)
#      Otherwise: run md_to_notion.py create → returns {page_id, url}
#   5. Save page_id to ~/.claude/state/spec-page-<title>
#   6. Print URL to stdout (caller prompts user to review)
#
# Errors exit non-zero with explanatory message to stderr.

set -euo pipefail

SKIP_UPLOAD=0
TITLE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --skip-upload) SKIP_UPLOAD=1; shift ;;
    --) shift; break ;;
    -*) echo "Error: unknown flag: $1" >&2; exit 1 ;;
    *)
      if [ -z "$TITLE" ]; then
        TITLE="$1"
      else
        echo "Error: extra positional argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [ -z "$TITLE" ]; then
  echo "Usage: spec-create.sh \"<title>\" [--skip-upload]" >&2
  exit 1
fi

# Validate title
if [[ -z "$TITLE" ]]; then
  echo "Error: title is empty" >&2
  exit 1
fi
if [[ "$TITLE" == *$'\n'* ]]; then
  echo "Error: title contains a newline" >&2
  exit 1
fi
if [[ "$TITLE" =~ ^[[:space:]] ]] || [[ "$TITLE" =~ [[:space:]]$ ]]; then
  echo "Error: title has leading or trailing whitespace" >&2
  exit 1
fi
if [[ "$TITLE" == *"/"* ]]; then
  echo "Error: title contains '/'" >&2
  exit 1
fi
if [[ "$TITLE" == *"|"* ]] || [[ "$TITLE" == *"&"* ]]; then
  echo "Error: title contains sed metacharacter '|' or '&' (please rename)" >&2
  exit 1
fi

# Detect target directory (git toplevel, or ~/.claude as fallback for non-git cwd)
TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -z "$TOPLEVEL" ]; then
  TOPLEVEL="$HOME/.claude"
  echo "Note: cwd is non-git; using fallback toplevel: $TOPLEVEL" >&2
fi
REPO_NAME=$(basename "$TOPLEVEL")

SPEC_DIR="$TOPLEVEL/docs/specs"
SPEC_FILE="$SPEC_DIR/$TITLE.md"
TEMPLATE="$HOME/.claude/skills/spec/templates/spec-default.md"

if [ ! -f "$TEMPLATE" ]; then
  echo "Error: template not found: $TEMPLATE" >&2
  exit 1
fi

STATE_DIR="$HOME/.claude/state"
STATE_FILE="$STATE_DIR/spec-page-$TITLE"

mkdir -p "$SPEC_DIR" "$STATE_DIR"

# md file: create from template if not exists, otherwise leave the existing one
if [ ! -f "$SPEC_FILE" ]; then
  sed "s|{{SLUG}}|$TITLE|g" "$TEMPLATE" > "$SPEC_FILE"
  echo "Created md: $SPEC_FILE" >&2
else
  echo "Using existing md: $SPEC_FILE" >&2
fi

if [ "$SKIP_UPLOAD" -eq 1 ]; then
  cat <<EOF
✓ md prepared (upload skipped).

  md file : $SPEC_FILE

Next steps (for c2):
  1. Edit each section of the md file with content drawn from prior conversation
  2. Run \`spec-create.sh "$TITLE"\` again (no --skip-upload) to upload to Notion
EOF
  exit 0
fi

if [ -f "$STATE_FILE" ]; then
  echo "Error: state file already exists: $STATE_FILE" >&2
  echo "  A Notion page was already created for this title. Use spec-update.sh to push edits, or spec-finalize.sh + start over." >&2
  exit 1
fi

# Upload to Notion
RESULT=$(python3 "$HOME/.claude/skills/spec/scripts/md_to_notion.py" create \
  --md "$SPEC_FILE" \
  --title "$TITLE" \
  --repo "$REPO_NAME")

PAGE_ID=$(echo "$RESULT" | python3 -c "import json,sys;print(json.load(sys.stdin)['page_id'])")
PAGE_URL=$(echo "$RESULT" | python3 -c "import json,sys;print(json.load(sys.stdin)['url'])")
UNIQUE_ID=$(echo "$RESULT" | python3 -c "import json,sys;print(json.load(sys.stdin).get('unique_id',''))")

echo "$PAGE_ID" > "$STATE_FILE"

if [ -n "$UNIQUE_ID" ]; then
  echo "$UNIQUE_ID" > "$STATE_DIR/spec-unique-id-$TITLE"
else
  echo "Warning: unique_id 取得失敗 (DB に Unique ID property がないか response 不在)" >&2
fi

cat <<EOF
✓ Spec created.

  md file : $SPEC_FILE
  Notion  : $PAGE_URL
  state   : $STATE_FILE
EOF
[ -n "$UNIQUE_ID" ] && echo "  unique_id : $UNIQUE_ID"
cat <<EOF

Next steps (for c2):
  1. If you edited the md after upload, run spec-update.sh "$TITLE" to push edits
  2. After user OK, run spec-finalize.sh "$TITLE" to delete local md + state
EOF
