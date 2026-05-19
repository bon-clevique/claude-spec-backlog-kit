#!/usr/bin/env bash
# plan-pr-target-resolver.sh — Resolve PR target repo for plan completion
#
# Provides:
#   resolve_pr_target_repo [changed_files...]  → echoes target repo info
#       outputs one of:
#         "case-b <git-toplevel>"   — cwd itself is a git project (Case B)
#         "case-a <git-toplevel>"   — cwd non-git, all changed files in single git repo (Case A)
#         "case-c"                  — cwd non-git, no PR target → archive (Case C)
#         "case-mixed <toplevel-1> <toplevel-2> ..."  — multi-repo span, abort/warn
#
# Detection order:
#   1. Case B: `git -C $PWD rev-parse --show-toplevel` succeeds → use cwd toplevel
#   2. Case A: cwd is non-git, but every changed file resides under exactly one
#      git toplevel → use that toplevel
#   3. Case C: cwd is non-git, no changed file is git-tracked → archive
#   4. Case mixed: changed files span multiple git toplevels → return all
#
# When no changed_files args supplied, callers should pass session-scoped diff
# from `git diff --name-only` per relevant repo. Callers are responsible for
# determining which files were modified.
#
# Self-test:
#   bash plan-pr-target-resolver.sh --self-test

set -euo pipefail

# Resolve git toplevel for a single path. Echoes empty string if not git-tracked.
_resolve_git_toplevel() {
  local path="$1"
  local dir
  if [[ -d "$path" ]]; then
    dir="$path"
  else
    dir=$(dirname "$path")
  fi
  (cd "$dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || echo ""
}

resolve_pr_target_repo() {
  # Case B: cwd is git project
  local cwd_toplevel
  cwd_toplevel=$(cd "$PWD" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || cwd_toplevel=""
  if [[ -n "$cwd_toplevel" ]]; then
    echo "case-b $cwd_toplevel"
    return 0
  fi

  # Case A/C/mixed: cwd is non-git, inspect changed files
  local -a changed_files=("$@")
  if [[ ${#changed_files[@]} -eq 0 ]]; then
    echo "case-c"
    return 0
  fi

  # Collect unique toplevels for changed files
  local -a toplevels=()
  local f tl seen
  for f in "${changed_files[@]}"; do
    [[ -z "$f" ]] && continue
    tl=$(_resolve_git_toplevel "$f")
    [[ -z "$tl" ]] && continue
    seen=0
    for existing in "${toplevels[@]+"${toplevels[@]}"}"; do
      if [[ "$existing" == "$tl" ]]; then
        seen=1
        break
      fi
    done
    if [[ "$seen" -eq 0 ]]; then
      toplevels+=("$tl")
    fi
  done

  case "${#toplevels[@]}" in
    0) echo "case-c" ;;
    1) echo "case-a ${toplevels[0]}" ;;
    *) printf 'case-mixed'; for tl in "${toplevels[@]}"; do printf ' %s' "$tl"; done; printf '\n' ;;
  esac
}

# Self-test
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ "${1:-}" == "--self-test" ]]; then
    set -e
    sandbox=$(mktemp -d)
    trap 'rm -rf "$sandbox"' EXIT

    # Setup: 2 git repos + 1 non-git tree + 1 non-git cwd
    repo_a="$sandbox/repo-a"
    repo_b="$sandbox/repo-b"
    nongit="$sandbox/nongit"
    cwd_nongit="$sandbox/cwd-nongit"
    mkdir -p "$repo_a" "$repo_b" "$nongit" "$cwd_nongit"
    git -C "$repo_a" init -q
    git -C "$repo_b" init -q
    touch "$repo_a/file1.txt" "$repo_a/file2.txt"
    touch "$repo_b/file3.txt"
    touch "$nongit/note.md"

    # Case 1: cwd is git toplevel → case-b
    out=$(cd "$repo_a" && resolve_pr_target_repo)
    [[ "$out" == "case-b "* ]] || { echo "FAIL case 1: expected case-b, got '$out'"; exit 1; }
    actual_top=$(echo "$out" | awk '{print $2}')
    actual_resolved=$(cd "$actual_top" && pwd -P)
    expected_resolved=$(cd "$repo_a" && pwd -P)
    [[ "$actual_resolved" == "$expected_resolved" ]] || { echo "FAIL case 1: toplevel mismatch ($actual_resolved != $expected_resolved)"; exit 1; }
    echo "PASS case 1: cwd is git → case-b"

    # Case 2: cwd non-git, all files in single repo → case-a
    out=$(cd "$cwd_nongit" && resolve_pr_target_repo "$repo_a/file1.txt" "$repo_a/file2.txt")
    [[ "$out" == "case-a "* ]] || { echo "FAIL case 2: expected case-a, got '$out'"; exit 1; }
    actual_top=$(echo "$out" | awk '{print $2}')
    actual_resolved=$(cd "$actual_top" && pwd -P)
    expected_resolved=$(cd "$repo_a" && pwd -P)
    [[ "$actual_resolved" == "$expected_resolved" ]] || { echo "FAIL case 2: toplevel mismatch ($actual_resolved != $expected_resolved)"; exit 1; }
    echo "PASS case 2: cwd non-git, single repo files → case-a"

    # Case 3: cwd non-git, no files → case-c
    out=$(cd "$cwd_nongit" && resolve_pr_target_repo)
    [[ "$out" == "case-c" ]] || { echo "FAIL case 3: expected case-c, got '$out'"; exit 1; }
    echo "PASS case 3: cwd non-git, no files → case-c"

    # Case 4: cwd non-git, only non-git files → case-c
    out=$(cd "$cwd_nongit" && resolve_pr_target_repo "$nongit/note.md")
    [[ "$out" == "case-c" ]] || { echo "FAIL case 4: expected case-c, got '$out'"; exit 1; }
    echo "PASS case 4: cwd non-git, only non-git files → case-c"

    # Case 5: cwd non-git, files span multiple repos → case-mixed
    out=$(cd "$cwd_nongit" && resolve_pr_target_repo "$repo_a/file1.txt" "$repo_b/file3.txt")
    [[ "$out" == "case-mixed "* ]] || { echo "FAIL case 5: expected case-mixed, got '$out'"; exit 1; }
    echo "PASS case 5: cwd non-git, multi-repo span → case-mixed"

    # Case 6: cwd non-git, mix of git-tracked and non-git files → case-a (non-git ignored)
    out=$(cd "$cwd_nongit" && resolve_pr_target_repo "$repo_a/file1.txt" "$nongit/note.md")
    [[ "$out" == "case-a "* ]] || { echo "FAIL case 6: expected case-a, got '$out'"; exit 1; }
    actual_top=$(echo "$out" | awk '{print $2}')
    actual_resolved=$(cd "$actual_top" && pwd -P)
    expected_resolved=$(cd "$repo_a" && pwd -P)
    [[ "$actual_resolved" == "$expected_resolved" ]] || { echo "FAIL case 6: toplevel mismatch ($actual_resolved != $expected_resolved)"; exit 1; }
    echo "PASS case 6: mix of tracked + non-git → case-a (non-git ignored)"

    echo "ALL PASS"
    exit 0
  fi

  # Default: print resolution for current cwd + supplied files
  resolve_pr_target_repo "$@"
fi
