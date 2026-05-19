#!/usr/bin/env node
/**
 * Stop hook: Warn about incomplete work before session ends
 * 1. Checks for uncommitted git changes
 * 2. Checks newest plan in ~/.claude/plans/ for unchecked boxes
 * 3. Writes an activity log entry to ~/.claude/activity.log
 * Always exits 0 — Stop hooks must never block (causes infinite loops)
 *
 * NOTE: This hook runs AFTER confirmation-leak-detector.js (order guaranteed in settings.json).
 *       It reads conf-leak-blocked-<sessionId> written by the detector.
 *
 * Hook ordering: 本 hook は Stop hooks 配列で **confirmation-leak-detector.js より後** に走る前提。
 * detector が書く `conf-leak-blocked-<sid>` flag を読んで suppress 判定。1-turn-consume 動作。
 * 詳細 → ~/.claude/scripts/hooks/HOOK-ORDER.md
 */

'use strict';

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const stateLib = require('./lib/state-paths');

const PLANS_DIR = path.join(process.env.HOME, '.claude', 'plans');
const ACTIVITY_LOG = path.join(process.env.HOME, '.claude', 'activity.log');
const MAX_STDIN = 1024 * 1024;

let data = '';
let globalSessionId = '';

process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => {
  if (data.length < MAX_STDIN) {
    data += c.substring(0, MAX_STDIN - data.length);
  }
});

process.stdin.on('end', () => {
  // Parse session_id from input for session-aware plan lookup
  try {
    const input = JSON.parse(data);
    const sid = (input.session_id || '').trim();
    if (sid && /^[\w.-]+$/.test(sid)) {
      globalSessionId = sid;
    }
  } catch {
    // Malformed JSON — use empty session ID (fallback to mtime)
  }

  // Pass through stdin unchanged.
  // 規約上の必須性は未確定だが、他 hook (e.g. detector) も pass-through しているため踏襲。
  // Stop hook で stdout への書き込みは hook 応答として解釈される可能性があり、安全のため
  // 入力を mirror する保守的方針。削除可否は別 plan で検証する (backlog: GZ1D)。
  process.stdout.write(data);

  try {
    checkGitStatus();
  } catch {
    // Not in a repo or git unavailable — skip silently
  }

  const suppressPlanWarn = isConfLeakBlocked(globalSessionId);

  // [NEW 2026-05-15] Draft PR 未作成検出 (Spec §8.3 / Plan humming-strolling-conway §4.1)
  try {
    if (!suppressPlanWarn) {
      checkDraftPRCreated(globalSessionId);
    }
  } catch {
    // Never crash — silently exit
  }

  try {
    if (suppressPlanWarn) {
      silentCheckPlans();
    } else {
      checkPlans();
    }
  } catch {
    // Never crash — silently exit
  }

  try {
    writeActivityLog();
  } catch {
    // Never crash — silently exit
  }

  try {
    checkDirectorResults();
  } catch {
    // Never crash — silently exit
  }

  // [NEW] Goal verify from Spec recap — warning only, never blocks
  // Synchronous: uses only sync fs APIs, no async/await needed.
  try {
    verifyGoalFromSpec(globalSessionId);
  } catch {
    // Never crash — silently exit
  }

  process.exit(0);
});

function checkGitStatus() {
  const result = execSync('git status --porcelain', {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'ignore'],
  });

  if (result && result.trim().length > 0) {
    process.stderr.write(
      '⚠️ Uncommitted changes detected. Run `gh pr create` or invoke Delivery Manager.\n'
    );
  }
}

function resolveProjectRoot() {
  try {
    return execSync('bash -c \'source "$HOME/.claude/scripts/lib/plan-cwd-resolver.sh"; plan_project_root\'', { encoding: 'utf8' }).trim();
  } catch { return ''; }
}

function getNewestPlanByMtime() {
  // Search order: <project>/.plans/active/ → ~/.claude/plans/active/ → ~/.claude/plans/
  const dirs = [];
  const projectRoot = resolveProjectRoot();
  if (projectRoot) dirs.push(path.join(projectRoot, '.plans', 'active'));
  dirs.push(path.join(PLANS_DIR, 'active'));
  dirs.push(PLANS_DIR);

  for (const dir of dirs) {
    if (!fs.existsSync(dir)) continue;
    const files = fs.readdirSync(dir)
      .filter((f) => f.endsWith('.md'))
      .map((f) => ({
        name: f,
        full: path.join(dir, f),
        mtime: fs.statSync(path.join(dir, f)).mtimeMs,
      }))
      .sort((a, b) => b.mtime - a.mtime);
    if (files.length === 0) continue;
    const content = fs.readFileSync(files[0].full, 'utf8');
    return { path: files[0].full, name: files[0].name, content };
  }
  return null;
}

function getActivePlan(sessionId) {
  // 1. Prefer session registry latest.path (session-specific, avoids mtime cross-session confusion)
  if (sessionId) {
    try {
      const latestRef = `/tmp/plan-registry-${sessionId}/latest.path`;
      if (fs.existsSync(latestRef)) {
        const planPath = fs.readFileSync(latestRef, 'utf8').trim();
        if (planPath && fs.existsSync(planPath)) {
          const content = fs.readFileSync(planPath, 'utf8');
          return { path: planPath, name: path.basename(planPath), content };
        }
      }
    } catch {
      // session_id present but registry missing/broken — fall through to Step 3 (mtime)
    }
  }

  // 2. Restore from previous-session registries — PostCompact recovery only.
  //    Skipped when sessionId is known: scanning /tmp/plan-registry-*/ across
  //    sessions causes cross-session plan misidentification (idle stalls in
  //    parallel sessions seed each other's "active plan").
  if (!sessionId) {
    try {
      const out = execSync(
        'ls -t /tmp/plan-registry-*/latest.path 2>/dev/null | head -5',
        { encoding: 'utf8' }
      ).trim();
      const registries = out.split('\n').filter(Boolean);
      for (const latestRef of registries) {
        try {
          const planPath = fs.readFileSync(latestRef, 'utf8').trim();
          if (planPath && fs.existsSync(planPath)) {
            const content = fs.readFileSync(planPath, 'utf8');
            return { path: planPath, name: path.basename(planPath), content };
          }
        } catch { /* try next */ }
      }
    } catch { /* fall through */ }
  }

  // 3. Fallback: newest by mtime (existing logic)
  return getNewestPlanByMtime();
}

// 5-minute TTL for conf-leak-blocked flag.
// Boundary: <= 300_000 ms → live, > 300_000 ms → stale (ignored).
// Anything older than the prompt-cache window means the session has effectively
// rolled over; honoring the flag would suppress a Stop hook for a different turn.
const CONF_LEAK_FLAG_TTL_MS = 5 * 60 * 1000;

function isConfLeakBlocked(sessionId) {
  if (!sessionId) return false;
  const stat = stateLib.statStateWithFallback('conf-leak-blocked', sessionId);
  if (!stat) return false;
  // TTL boundary: stale flags do not suppress the warning, but are still consumed
  // so they don't leak across sessions.
  const ageMs = Date.now() - stat.mtimeMs;
  stateLib.unlinkState('conf-leak-blocked', sessionId);
  if (ageMs > CONF_LEAK_FLAG_TTL_MS) return false;
  return true;
}

function silentCheckPlans() {
  const plan = getActivePlan(globalSessionId);
  if (!plan) return;

  const lines = plan.content.split('\n');
  const unchecked = [];
  for (const line of lines) {
    const m = line.match(/^\s*-\s\[(\s|~)\]\s*(.*)$/);
    if (m) {
      const title = m[2].trim();
      if (title) unchecked.push(title);
    }
  }

  if (unchecked.length === 0) return;

  // stderr には何も出さない。activity.log にのみ記録 (リスク §6.4 対策 2)
  try {
    const nowJst = new Date(Date.now() + 9 * 60 * 60 * 1000);
    const ts = nowJst.toISOString().replace('T', ' ').slice(0, 19);
    const logLine = `[GATE-SUPPRESSED] ${ts} | session=${globalSessionId} | plan=${plan.name} | unchecked=${unchecked.length}\n`;
    const fd = fs.openSync(ACTIVITY_LOG, 'a', 0o600);
    try { fs.writeSync(fd, logLine); } finally { fs.closeSync(fd); }
  } catch { /* fail silently */ }
}

// [NEW 2026-05-15] Draft PR 未作成 warning (Spec §8.3 / Plan §4.1)
// plan-approved 中に Draft PR (~/.claude/state/draft-pr-created-<sid>) 未作成なら warn (block しない)
function checkDraftPRCreated(sessionId) {
  if (!sessionId) return;

  // Escape valve
  if (process.env.DRAFT_PR_GATE_OFF === '1') return;

  const stateDir = path.join(process.env.HOME, '.claude', 'state');
  let planApprovedExists = false;

  // Stack-aware: top plan-id があればそれを優先
  try {
    const topPlanId = stateLib.peekPlanStack ? stateLib.peekPlanStack(sessionId) : null;
    if (topPlanId) {
      planApprovedExists = fs.existsSync(path.join(stateDir, `plan-approved-${sessionId}-${topPlanId}`));
    }
  } catch {
    // peekPlanStack 失敗 → legacy fallback へ
  }

  if (!planApprovedExists) {
    // Legacy session-wide flag fallback
    planApprovedExists = fs.existsSync(path.join(stateDir, `plan-approved-${sessionId}`));
  }

  if (!planApprovedExists) return; // Plan Mode 中 / 未承認 → check 不要

  // Draft PR 作成済 flag 確認
  const draftPRFile = path.join(stateDir, `draft-pr-created-${sessionId}`);
  if (fs.existsSync(draftPRFile)) return; // 作成済み → OK

  // Warning 出力 (block しない)
  process.stderr.write(
    '⚠️ Draft PR 未作成: Plan を承認しましたが Draft PR が作成されていません。\n' +
    '   `bash ~/.claude/scripts/create-draft-pr.sh <plan-file>` を実行してください。\n' +
    '   詳細: ~/.claude/rules/_lazy/delivery.md §Plan 承認直後 Draft PR 作成\n' +
    '   Escape: DRAFT_PR_GATE_OFF=1\n'
  );
}

function checkPlans() {
  const plan = getActivePlan(globalSessionId);
  if (!plan) return;

  const lines = plan.content.split('\n');
  const unchecked = [];
  for (const line of lines) {
    const m = line.match(/^\s*-\s\[(\s|~)\]\s*(.*)$/);
    if (m) {
      const title = m[2].trim();
      if (title) unchecked.push(title);
    }
  }

  if (unchecked.length === 0) return;

  const MAX_SHOW = 8;
  const shown = unchecked.slice(0, MAX_SHOW);
  const rest = unchecked.length - shown.length;

  process.stderr.write(
    `⚠️ Plan has ${unchecked.length} incomplete step(s) in ${plan.name}:\n`
  );
  for (const title of shown) {
    process.stderr.write(`   - [ ] ${title}\n`);
  }
  if (rest > 0) {
    process.stderr.write(`   ... and ${rest} more\n`);
  }
  process.stderr.write(
    '   Completion criterion: all plan checkboxes must be [x] AND the user can execute the original goal end-to-end.\n' +
    '   If steps do not cover the original goal, the plan itself is incomplete — revise it, do not declare done.\n'
  );
}

function writeActivityLog() {
  const now = new Date();
  // Format as JST (UTC+9)
  const jstOffset = 9 * 60 * 60 * 1000;
  const jst = new Date(now.getTime() + jstOffset);
  const timestamp = jst.toISOString().replace('T', ' ').substring(0, 16);

  const cwd = process.cwd();
  // Shorten home dir paths
  const shortCwd = cwd.replace(process.env.HOME, '~');

  const plan = getActivePlan(globalSessionId);
  let summary;
  let next;

  if (!plan) {
    summary = 'no plan';
    next = 'no plan';
  } else {
    const lines = plan.content.split('\n');
    const checked = lines.filter((l) => /^\s*-\s*\[x\]/i.test(l));
    const unchecked = lines.filter((l) => /^\s*-\s*\[\s\]/.test(l) || /^\s*-\s*\[~\]/.test(l));
    const total = checked.length + unchecked.length;

    // Extract plan name from filename (remove .md extension)
    const planName = plan.name.replace(/\.md$/, '');

    if (total === 0) {
      summary = planName;
      next = 'no items';
    } else if (unchecked.length === 0) {
      summary = `${planName} (${total}/${total} done)`;
      next = 'all done';
    } else {
      summary = `${planName} (${checked.length}/${total} done)`;
      next = `${unchecked.length} remaining`;
    }
  }

  // Truncate to keep line under 200 chars
  const line = `[${timestamp}] ${shortCwd} | done: ${summary} | next: ${next}`;
  const truncated = line.length > 200 ? line.substring(0, 197) + '...' : line;

  try {
    const fd = fs.openSync(ACTIVITY_LOG, 'a', 0o600);
    try { fs.writeSync(fd, truncated + '\n'); } finally { fs.closeSync(fd); }
  } catch { /* best-effort */ }
}

function checkDirectorResults() {
  const resultsDir = path.join(process.env.HOME, '.claude', 'director-results');
  if (!fs.existsSync(resultsDir)) return;
  const files = fs.readdirSync(resultsDir)
    .filter(f => f.endsWith('.md') && !f.endsWith('.read.md'))
    .sort();
  if (files.length === 0) return;
  process.stderr.write(
    `📋 ${files.length} unread Director result(s) in ~/.claude/director-results/:\n` +
    files.slice(0, 5).map(f => `   - ${f}`).join('\n') + '\n' +
    '   Rename to <name>.read.md after reviewing.\n'
  );
}

// [NEW] Goal verify from Spec §🔁 recap section.
// Reads the active plan file, extracts the §🔁 recap body, and warns (no block)
// if the「完了:」line is missing or too short — a signal that Spec §3 Goal
// achievement state wasn't properly recorded.
//
// Escape valve: GOAL_VERIFY_OFF=1 — disable entirely.
// Always returns gracefully; failures never affect exit code.
function verifyGoalFromSpec(sessionId) {
  if (process.env.GOAL_VERIFY_OFF === '1') return null;
  if (!sessionId) return null;

  const stateDir = path.join(process.env.HOME, '.claude', 'state');

  // Stack-aware: prefer per-plan plan-current state, fall back to legacy
  let planFile = '';
  try {
    const stackFile = path.join(stateDir, `plan-stack-${sessionId}`);
    if (fs.existsSync(stackFile)) {
      const stack = fs.readFileSync(stackFile, 'utf-8').trim().split('\n').filter(Boolean);
      if (stack.length > 0) {
        const top = stack[stack.length - 1];
        const perPlanFile = path.join(stateDir, `plan-current-${sessionId}-${top}`);
        if (fs.existsSync(perPlanFile)) {
          planFile = fs.readFileSync(perPlanFile, 'utf-8').trim();
        }
      }
    }
    if (!planFile) {
      const legacyFile = path.join(stateDir, `plan-current-${sessionId}`);
      if (fs.existsSync(legacyFile)) {
        planFile = fs.readFileSync(legacyFile, 'utf-8').trim();
      }
    }
  } catch {
    return null;
  }

  if (!planFile || !fs.existsSync(planFile)) {
    // Silent skip observability: log so the cause of no warning is auditable
    try {
      const nowJst = new Date(Date.now() + 9 * 60 * 60 * 1000);
      const ts = nowJst.toISOString().replace('T', ' ').slice(0, 19);
      const fd = fs.openSync(ACTIVITY_LOG, 'a', 0o600);
      try {
        fs.writeSync(fd, `[GOAL-VERIFY-SKIP] ${ts} | session=${sessionId} | reason=no-plan-current\n`);
      } finally { fs.closeSync(fd); }
    } catch { /* best-effort */ }
    return null;
  }

  let planContent = '';
  try {
    planContent = fs.readFileSync(planFile, 'utf-8');
  } catch {
    return null;
  }

  // Confirm a corresponding Spec exists (Notion URL anywhere in plan, typically header).
  // Tightened to require ≥16 char path segment to reduce false-positive matches.
  // Without a Spec, recap verification is N/A.
  if (!/notion\.so\/[a-z0-9-]{16,}/i.test(planContent)) return null;

  // Extract §🔁 recap section body (until next H2 or EOF)
  const recapMatch = planContent.match(/##\s+🔁\s+recap\s*\n([\s\S]*?)(?=\n##\s|\n*$)/);
  if (!recapMatch) return null;

  const recapText = recapMatch[1];
  const doneMatch = recapText.match(/完了:\s*(.+)/);

  if (!doneMatch || doneMatch[1].trim().length < 5) {
    process.stderr.write(
      '⚠️ [GOAL-VERIFY-WARN] recap §🔁 の「完了:」行が空または短すぎます。\n' +
      '   Spec §3 Goal の達成状態を recap に明記してください。\n' +
      '   Escape: GOAL_VERIFY_OFF=1\n'
    );
    return 'warn';
  }

  return 'ok';
}
