#!/usr/bin/env node
/**
 * PostToolUse: ExitPlanMode | EnterPlanMode — manage plan approval state.
 *
 * EnterPlanMode: sets plan-mode-active flag (consumed by plan-gate.js).
 * ExitPlanMode:  resolves plan path via plan-current-<sid> (written by
 *                plan-current-recorder.js on Write), writes plan-approved-<sid>.
 *
 * Plan path resolution is now deterministic — find/mtime heuristics and
 * heading validation are removed (see plan cached-sniffing-waffle §3.1, §3.5).
 *
 * Exit 0 always — never blocks the user.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const stateLib = require('./lib/state-paths');

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
  } catch (err) {
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

  const toolName = input.tool_name || '';
  const sessionId = (input.session_id || '').trim();

  if (!sessionId) {
    process.exit(0);
  }

  // Guard against path traversal: session_id must be a safe identifier
  if (!/^[\w.-]+$/.test(sessionId)) {
    process.exit(0);
  }

  // EnterPlanMode → set plan-mode-active flag (plan-gate reads this to allow plan file Writes
  // before plan-current-<sid> exists), and clear plan-in-execution flag.
  if (toolName === 'EnterPlanMode') {
    stateLib.writeStateAtomic('plan-mode-active', sessionId, '');
    try { stateLib.unlinkState('plan-in-execution', sessionId); } catch { /* best-effort */ }
    process.exit(0);
  }

  if (toolName !== 'ExitPlanMode') {
    process.exit(0);
  }

  // Check tool_response for error signals — if it has an explicit error, don't mark approved.
  // Verified in session 4a0516f2: ExitPlanMode returned tool_use_error and Plan Mode remained
  // active server-side.
  const response = input.tool_response;
  if (response && typeof response === 'object' && response.error) {
    process.exit(0);
  }

  // (6-a) Yes/No degraded-UI defense: require plan-mode-active flag (added 2026-05-12)
  // If plan-mode-active-<sid> state file is missing, the harness is not actually in
  // Plan Mode (e.g., the prompt degraded to a bare "Exit plan mode? Yes/No" and user
  // tapped Yes). Refuse to set plan-approved to avoid false approvals.
  // Stack-aware: use top planId from plan stack if present; falls back to legacy.
  const topPlanId = (() => {
    try { return stateLib.peekPlanStack(sessionId); } catch { return null; }
  })();
  if (process.env.PLAN_APPROVAL_MARKER_OFF !== '1') {
    const planModeActive = topPlanId
      ? stateLib.statPlanStateWithLegacyFallback('plan-mode-active', sessionId, topPlanId)
      : stateLib.statStateWithFallback('plan-mode-active', sessionId);
    if (!planModeActive) {
      appendActivityLog(`[PLAN-APPROVAL-SKIP] sid=${sessionId} reason=no-plan-mode-active-flag`);
      process.exit(0);
    }
  }

  // Detect misuse of legacy `plan` argument (current schema takes no plan content; harness
  // reads the plan file directly). Logging only — do not block (UX preservation). Added
  // 2026-05-10 after session f9b40efa where c2 passed stale rev.2 string in the plan arg
  // while the file on disk was rev.4, causing cognitive divergence.
  const toolInput = input.tool_input || {};
  if (typeof toolInput.plan === 'string' && toolInput.plan.length > 0) {
    appendActivityLog(`[PLAN-ARG-MISUSE] sid=${sessionId} plan-arg-len=${toolInput.plan.length}`);
  }

  // (6-b) Yes/No degraded-UI defense: plan-arg non-empty (added 2026-05-12)
  // The current ExitPlanMode schema takes no plan content. Non-empty tool_input.plan
  // is a strong signal of state inconsistency or Yes/No prompt degradation. Skip
  // approval to prevent false-positive plan-approved flags.
  if (typeof toolInput.plan === 'string' && toolInput.plan.length > 0) {
    appendActivityLog(`[PLAN-APPROVAL-SKIP] sid=${sessionId} reason=plan-arg-misuse plan-arg-len=${toolInput.plan.length}`);
    process.exit(0);
  }

  // Resolve plan file via plan-current-<sid> (written by plan-current-recorder.js on Write).
  // This is the deterministic path — no find heuristics, no heading regex.
  // Stack-aware: prefer per-plan state via top planId; falls back to legacy.
  const planPath = readCurrentPlanPath(sessionId, topPlanId);

  if (!planPath) {
    // No plan-current state: plan was not written in this session or recorder missed it.
    // Do not set plan-approved to avoid spurious approval.
    appendActivityLog(`[PLAN-APPROVAL-SKIP] sid=${sessionId} reason=no-plan-current-state`);
    process.exit(0);
  }

  // All sanity checks passed — proceed with normal approval flow.

  // Write plan-approved flag (downstream: plan-gate.js, confirmation-leak-detector.js)
  // Legacy write is preserved for backward compatibility. If a top planId is present
  // on the plan stack, also write a per-plan plan-approved entry so stack-aware
  // consumers can resolve approval state for the specific plan.
  stateLib.writeStateAtomic('plan-approved', sessionId, '');
  if (topPlanId) {
    try { stateLib.writePlanStateAtomic('plan-approved', sessionId, topPlanId, ''); } catch { /* best-effort */ }
  }

  // Clear plan-mode-active flag on successful ExitPlanMode (Plan Mode is exited).
  // Stack-aware: also clear per-plan plan-mode-active when a top planId is present.
  try { stateLib.unlinkState('plan-mode-active', sessionId); } catch { /* best-effort */ }
  if (topPlanId) {
    try { stateLib.unlinkPlanState('plan-mode-active', sessionId, topPlanId); } catch { /* best-effort */ }
  }

  // Write plan registry for completion-gate.js to find the session-specific plan.
  try {
    const registryDir = `/tmp/plan-registry-${sessionId}`;
    fs.mkdirSync(registryDir, { recursive: true });
    const planBasename = path.basename(planPath, '.md');
    fs.writeFileSync(path.join(registryDir, `${planBasename}.path`), planPath, 'utf8');
    fs.writeFileSync(path.join(registryDir, 'latest.path'), planPath, 'utf8');
  } catch {
    // Fail silently — registry is best-effort
  }

  process.exit(0);
}

/**
 * Read the plan path recorded by plan-current-recorder.js.
 * Returns the trimmed absolute path, or '' if not found.
 *
 * Stack-aware: when a top planId is supplied, resolve via per-plan
 * plan-current state first, falling back to the legacy single-slot state.
 */
function readCurrentPlanPath(sessionId, topPlanId) {
  try {
    const raw = topPlanId
      ? stateLib.readPlanStateWithLegacyFallback('plan-current', sessionId, topPlanId)
      : stateLib.readStateWithFallback('plan-current', sessionId);
    if (!raw) return '';
    return raw.trim();
  } catch {
    return '';
  }
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
