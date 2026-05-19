#!/usr/bin/env bash
# mini-da-template.sh — Documentation/utility for Mini-DA Gate
#
# This is NOT a hook. It is reference documentation that main session
# uses to decide how to invoke the mini-da sub-agent.
#
# Usage (from main session conceptually):
#   1. Check MINI_DA_OFF env var; if set, skip
#   2. Compose invocation prompt with Candidate / Plan Context / PR Context
#   3. Call: Agent({subagent_type: "mini-da", model: "opus", prompt: <composed>})
#   4. Parse the last line ("VERDICT: <kind>") and dispatch:
#      - proceed-light → continue implementation
#      - propose-plan-mode → 1-line user suggestion to enter Plan Mode
#      - defer-to-backlog → backlog-task-manager (midexec mode)
#      - split-task → backlog-task-manager (midexec mode) + continue current task
#   5. Log to ~/.claude/activity.log: [MINI-DA] <verdict>: <one-line summary>
#
# This script can be sourced or executed standalone to print the canonical
# invocation template for human reference.

set -euo pipefail

cat <<'EOF'
# Mini-DA Gate invocation template (canonical reference)

Step 1: Check opt-out
  $ [ "${MINI_DA_OFF:-0}" = "1" ] && exit 0  # skip Mini-DA, proceed directly

Step 2: Compose prompt (from main session, conceptually)
  Candidate: <one-line description of mid-execution addition>
  Current Plan Context: <plan §1.2 Goal sentence, or "no active plan">
  Current PR Context: <PR title / branch / state, or "no recent PR">

Step 3: Invoke
  Agent({subagent_type: "mini-da", model: "opus", prompt: <composed>})

Step 4: Parse verdict (last line)
  - "VERDICT: proceed-light"     → continue implementation
  - "VERDICT: propose-plan-mode" → suggest manual Plan Mode (1 sentence)
  - "VERDICT: defer-to-backlog"  → backlog-task-manager (midexec)
  - "VERDICT: split-task"        → backlog-task-manager (midexec) + continue

Step 5: Log
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [MINI-DA] <verdict>: <summary>" >> ~/.claude/activity.log

Environment variables:
  MINI_DA_OFF=1                  Skip Mini-DA entirely
  MINI_DA_LOG_VERBOSE=1          Include 3 sub-question answers in log (default: verdict only)
EOF
