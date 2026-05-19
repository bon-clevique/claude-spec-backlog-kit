#!/usr/bin/env node
/**
 * PreToolUse: Edit | Write | MultiEdit — deny when plan has agent-required marker
 * and the caller is main session (not a sub-agent).
 *
 * Context: plan-gate.js is now default permissive (2026-05-11 refactor). It only
 * denies Writes to plan file paths when Plan Mode is not active. This hook activates
 * only when plan-approved-<sid> is present AND an <!-- agent-required: <type> --> marker
 * exists in the active plan — enforcing sub-agent delegation even after approval.
 *
 * Decision flow:
 *   1. PLAN_ENFORCE_OFF=1                  → exit 0 (full bypass)
 *   2. tool_name not in {Edit,Write,MultiEdit} → exit 0
 *   3. session_id invalid                  → exit 0
 *   4. plan-approved-<sid> missing         → exit 0 (plan-gate handles unapproved case)
 *   5. plan-current-<sid> unreadable       → exit 0 (cannot identify plan)
 *   6. plan content unreadable             → exit 0
 *   7. file_path == plan file itself       → exit 0 (allow plan self-edits)
 *   8. is_subagent(input)                  → exit 0 (sub-agents are authorised)
 *   9. scan plan for <!-- agent-required: <type> --> markers across all sections
 *  10. no marker found                     → exit 0 (plain plan, no enforcement)
 *  11. PLAN_ENFORCE_DRY_RUN=1              → warn stderr, exit 0
 *  12. deny: log to activity.log + emit hook JSON
 *
 * Sub-agent detection (is_subagent):
 *   Plan A: input.agent_id is a non-empty string → sub-agent
 *   Plan B: read transcript_path, scan last N lines for isSidechain:true → sub-agent
 *   Either condition satisfying → sub-agent (allow)
 */

'use strict';

const fs   = require('fs');
const path = require('path');
const stateLib = require('./lib/state-paths');
const { isSubagent } = require('./lib/subagent-detect');

const MARKER_RE  = /<!--\s*agent-required:\s*([a-z][a-z0-9-]*)\s*-->/;
const SID_RE     = /^[\w.-]+$/;
const MAX_STDIN  = 1024 * 1024;
const ACTIVITY_LOG = path.join(process.env.HOME, '.claude', 'activity.log');

let data = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  if (data.length < MAX_STDIN) data += chunk.substring(0, MAX_STDIN - data.length);
});
process.stdin.on('end', () => {
  try { run(); } catch { process.exit(0); }
});

function run() {
  // (1) bypass env
  if (process.env.PLAN_ENFORCE_OFF === '1') process.exit(0);

  // Parse input
  let input;
  try { input = JSON.parse(data); } catch { process.exit(0); }

  // (2) tool filter
  const toolName = input.tool_name || '';
  if (!['Edit', 'Write', 'MultiEdit'].includes(toolName)) process.exit(0);

  // (3) session_id validation
  const sessionId = (input.session_id || '').trim();
  if (!sessionId || !SID_RE.test(sessionId)) process.exit(0);

  // (4) plan-approved must exist (plan-gate handles the unapproved case)
  const approved = stateLib.statStateWithFallback('plan-approved', sessionId);
  if (!approved) process.exit(0);

  // (5) plan-current must be readable
  const planCurrentRaw = stateLib.readStateWithFallback('plan-current', sessionId);
  if (!planCurrentRaw) process.exit(0);
  const planPath = planCurrentRaw.trim();
  if (!planPath) process.exit(0);

  // (6) plan content must be readable
  let planContent;
  try { planContent = fs.readFileSync(planPath, 'utf8'); } catch { process.exit(0); }

  // (7) allow edits to the plan file itself
  const filePath = String((input.tool_input || {}).file_path || '');
  if (filePath && path.resolve(filePath) === path.resolve(planPath)) process.exit(0);

  // (8) allow sub-agents
  if (isSubagent(input)) process.exit(0);

  // (9) scan plan for any agent-required marker
  const markerType = findMarker(planContent);

  // (10) no marker → plain plan, no enforcement
  if (!markerType) process.exit(0);

  // (11) dry-run mode
  if (process.env.PLAN_ENFORCE_DRY_RUN === '1') {
    process.stderr.write(
      `[plan-enforce] WARN (dry-run): ${toolName} on ${filePath} would be denied ` +
      `(agent-required: ${markerType} exists in plan ${planPath})\n`
    );
    process.exit(0);
  }

  // (12) deny
  appendActivityLog(sessionId, toolName, filePath, markerType, planPath);
  const reason = buildDenyReason(markerType);
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason: reason,
    },
  }));
  process.exit(0);
}

/**
 * Scan plan content for any <!-- agent-required: <type> --> marker.
 * Returns the first marker type found, or null if none.
 * Heading lines only reset context for future sections — finding any marker
 * in the entire plan is sufficient to activate enforcement (plan-wide scope).
 */
function findMarker(content) {
  const lines = content.split('\n');
  for (const line of lines) {
    const m = MARKER_RE.exec(line);
    if (m) return m[1];
  }
  return null;
}


function buildDenyReason(agentType) {
  return (
    `[plan-enforce] Edit/Write を deny: plan に <!-- agent-required: ${agentType} --> marker ` +
    `が存在し、現在 main session から直接 Edit を試みています。\n\n` +
    `解決: Agent tool で ${agentType} sub-agent を起動して実装を委譲してください。\n` +
    `  例: Agent(subagent_type="${agentType}", prompt="<具体的な作業内容>")\n\n` +
    `例外操作 (deny 対象外): plan file 自体の Edit / Read tool\n` +
    `緊急 bypass: 該当 marker を plan から外す or PLAN_ENFORCE_OFF=1`
  );
}

function appendActivityLog(sid, tool, filePath, agentType, planPath) {
  try {
    const ts = new Date().toISOString();
    const line = `${ts} [PLAN-ENFORCE-DENY] sid=${sid} tool=${tool} path=${filePath} required=${agentType} plan=${planPath}\n`;
    const fd = fs.openSync(ACTIVITY_LOG, 'a', 0o600);
    try { fs.writeSync(fd, line); } finally { fs.closeSync(fd); }
  } catch { /* log failure is non-fatal */ }
}
