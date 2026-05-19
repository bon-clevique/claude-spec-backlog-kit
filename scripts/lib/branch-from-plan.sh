#!/usr/bin/env bash
# branch-from-plan.sh — Convert a harness-issued plan slug to a feature branch name.
#
# Usage:
#   branch-from-plan.sh <plan-slug>
#
# Strips the trailing ".md" (if present) and removes a leading
# UUID prefix (^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}-)
# inserted by the Claude Code harness, then prints "feature/<tail>" to stdout.
# If no UUID prefix is present, the slug itself is used as the tail.
#
# Examples:
#   <UUID>-draft-pr-prep.md
#       → feature/draft-pr-prep
#   humming-strolling-conway.md
#       → feature/humming-strolling-conway
#   <UUID>-foo
#       → feature/foo
#
# Exit codes:
#   0 on success, 1 if no slug argument was supplied.

set -euo pipefail

if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
  echo "Usage: branch-from-plan.sh <plan-slug>" >&2
  exit 1
fi

slug="$1"

# Strip trailing ".md" if present
slug="${slug%.md}"

# Strip leading UUID prefix (8-4-4-4-12 hex chars + trailing dash) if present
tail=$(printf '%s\n' "$slug" | sed -E 's/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}-//')

# tail is empty only if the input was *exactly* a UUID + dash and nothing else;
# fall back to the original slug to avoid emitting "feature/".
if [ -z "$tail" ]; then
  tail="$slug"
fi

printf 'feature/%s\n' "$tail"
