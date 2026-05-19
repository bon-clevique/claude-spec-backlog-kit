#!/usr/bin/env bash
# project-slug.sh — Derive backlog project-slug from cwd or arbitrary path
#
# Provides:
#   project_slug_from_path <abs_path>  → echoes the slug, or "_global"
#
# Rule:
#   abs_path → strip <project-root>/ prefix → replace "/" with "-" → lowercase
#   Special: paths outside <project-root>/, or <project-root>/.claude/backlog/ itself, → "_global"
#
# Project root resolution (in order of precedence):
#   1. $BACKLOG_PROJECT_ROOT (if set and non-empty)
#   2. $HOME/dev (default)
#
# Usage:
#   source ~/.claude/scripts/lib/project-slug.sh
#   slug=$(project_slug_from_path "$PWD")

project_slug_from_path() {
  local input="${1:-$PWD}"
  local abs

  # Resolve to absolute, real path; fall back to input if path doesn't exist
  abs=$(cd "$input" 2>/dev/null && pwd -P) || abs="$input"

  local devroot="${BACKLOG_PROJECT_ROOT:-$HOME/dev}"
  # Resolve devroot to its real path so comparisons work even when it contains
  # a relative or symlinked path. Fall back to the raw value if it doesn't exist.
  local devroot_resolved
  devroot_resolved=$(cd "$devroot" 2>/dev/null && pwd -P) || devroot_resolved="$devroot"
  devroot="$devroot_resolved"

  # Outside <project-root> → _global
  case "$abs" in
    "$devroot"/*) ;;
    "$devroot")    echo "_global"; return 0 ;;
    *)             echo "_global"; return 0 ;;
  esac

  # Strip the <project-root>/ prefix
  local rel="${abs#$devroot/}"

  # Special case: <project-root> itself acts as the meta-project (legacy "_global" host)
  # When invoked from <project-root> or <project-root>/.claude/..., treat as _global
  case "$rel" in
    ".claude"|".claude/"*) echo "_global"; return 0 ;;
    "")                    echo "_global"; return 0 ;;
  esac

  # Find the project root: the path up to (but not including) any .claude/ segment.
  # If the path contains /.claude/ or ends with /.claude, truncate before it.
  local project_rel="${rel%%/.claude*}"

  # Convert "/" and any non-[a-z0-9-] chars → "-", then lowercase, then collapse repeats
  local slug
  slug=$(printf '%s\n' "$project_rel" \
         | tr '[:upper:]' '[:lower:]' \
         | sed 's|[^a-z0-9-]|-|g; s|--*|-|g; s|^-||; s|-$||')

  # Cap at 50 chars (slug regex: ^[a-z0-9][a-z0-9-]{0,49}$)
  if [[ ${#slug} -gt 50 ]]; then
    slug="${slug:0:50}"
    slug="${slug%-}"
  fi

  echo "$slug"
}

# If invoked as a script: derive slug from $1 or $PWD
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  project_slug_from_path "${1:-$PWD}"
fi
