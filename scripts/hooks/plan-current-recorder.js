#!/usr/bin/env node
/**
 * PostToolUse: Write — record the plan file path to plan-current-<session_id>.
 *
 * When c2 writes a plan file (under ~/.claude/plans/<slug>.md), this hook
 * captures the absolute path so that plan-approval-marker.js can later
 * resolve it deterministically instead of relying on find/mtime heuristics.
 *
 * Decision flow:
 *   1. Parse stdin JSON
 *   2. Extract tool_input.file_path
 *   3. Check isActivePlanPath() — $HOME/.claude/plans/<slug>.md only
 *      (archived/ and active/ subdirectories are excluded)
 *   4. On match: write absolute path to ~/.claude/state/plan-current-<sid>
 *   5. Exit 0 always — never blocks the user
 */

'use strict';

const path = require('path');
const fs = require('fs');
const stateLib = require('./lib/state-paths');

const PLANS_ROOT = path.join(process.env.HOME || '', '.claude', 'plans');
function isActivePlanPath(p) {
  if (!p || typeof p !== 'string') return false;
  if (p.indexOf(PLANS_ROOT + '/') !== 0) return false;
  const rest = p.substring(PLANS_ROOT.length + 1);
  return /^[^/]+\.md$/.test(rest);
}

const MAX_STDIN = 1024 * 1024;
let data = '';

process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  if (data.length < MAX_STDIN) {
    data += chunk.substring(0, MAX_STDIN - data.length);
  }
});

process.stdin.on('end', () => {
  try {
    run();
  } catch {
    // Never crash — silently exit 0
    process.exit(0);
  }
});

function run() {
  let input;
  try {
    input = JSON.parse(data);
  } catch {
    // Malformed JSON — nothing to do
    process.exit(0);
  }

  const sessionId = (input.session_id || '').trim();
  if (!sessionId) process.exit(0);

  // Guard against path traversal: session_id must be a safe identifier
  if (!/^[\w.-]+$/.test(sessionId)) process.exit(0);

  const toolInput = input.tool_input || {};
  const filePath = String(toolInput.file_path || '');

  // Only record plan files under ~/.claude/plans/ active root (no subdirectories)
  if (!isActivePlanPath(filePath)) process.exit(0);

  // Extract plan-id from filename (e.g., "concurrent-stirring-sunbeam.md" → "concurrent-stirring-sunbeam")
  const planId = path.basename(filePath, '.md');

  // Write per-plan namespaced state (new contract for stack-aware lookups)
  try {
    stateLib.writePlanStateAtomic('plan-current', sessionId, planId, filePath + '\n');
  } catch { /* invalid planId or fs error — fall through to legacy write */ }

  // Defensive dual-write: also create per-plan plan-mode-active flag.
  // EnterPlanMode handler in plan-approval-marker.js only writes the session-wide
  // legacy flag because plan-id is not yet known at EnterPlanMode time. When the
  // first plan-file Write resolves the plan-id, propagate the active flag to the
  // per-plan namespace so future readers (plan-gate.js / confirmation-leak-detector.js)
  // remain correct even if the legacy write is later removed (review HIGH 2026-05-12).
  try {
    if (stateLib.statStateWithFallback('plan-mode-active', sessionId)) {
      stateLib.writePlanStateAtomic('plan-mode-active', sessionId, planId, '');
    }
  } catch { /* best-effort */ }

  // Maintain plan stack (idempotent push when top != planId)
  try {
    const top = stateLib.peekPlanStack(sessionId);
    if (top !== planId) {
      stateLib.pushPlanStack(sessionId, planId);
      const depth = stateLib.readPlanStack(sessionId).length;
      appendActivityLog(`[PLAN-STACK-PUSH] sid=${sessionId} plan-id=${planId} depth=${depth}`);
    }
  } catch { /* best-effort stack maintenance */ }

  // Legacy state write (backward compatibility — read sites still fall back to this)
  stateLib.writeStateAtomic('plan-current', sessionId, filePath + '\n');

  process.exit(0);
}

function appendActivityLog(line) {
  try {
    const HOME = process.env.HOME;
    const logPath = path.join(HOME, '.claude', 'activity.log');
    const ts = new Date().toISOString();
    const fd = fs.openSync(logPath, 'a', 0o600);
    try { fs.writeSync(fd, `${ts} ${line}\n`); } finally { fs.closeSync(fd); }
  } catch { /* best-effort */ }
}
