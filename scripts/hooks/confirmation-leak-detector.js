#!/usr/bin/env node
/**
 * Stop hook: Detect confirmation-leak patterns in the last assistant message.
 *
 * Only fires when a plan was approved in this session (flag plan-approved-<session_id>
 * must exist in ~/.claude/state/). Approved plans pre-authorize all steps — asking
 * "shall I proceed?" is a regression.
 *
 * 3 categories of leak patterns:
 *   FWD  — forward-seeking ("shall I proceed?", "進めますか" etc.)
 *   BWD  — backward-seeking ("ここで止めて", "Plan Mode で改めて" etc.)
 *   MC   — multi-choice ("(1)....(2)....どうしますか" etc.)
 *
 * Matching: block JSON to stdout (decision:"block") + appends to ~/.claude/activity.log.
 * Block capped at 2 per session (state: ~/.claude/state/conf-leak-block-count-<sessionId>).
 * Dry-run mode: CONF_LEAK_DRY_RUN=1 → warning only, no block.
 * Exit 0 always — Stop hook must never crash.
 *
 * SCOPE_CUT_RE is warning-only, independent of the 3-category block logic.
 *
 * NOTE: This hook must run BEFORE completion-gate.js (order guaranteed in settings.json).
 *       It writes conf-leak-blocked-<sessionId> which completion-gate reads.
 *
 * Hook ordering: 本 hook は Stop hooks 配列で **completion-gate.js より先** に走る前提。
 * 詳細 → ~/.claude/scripts/hooks/HOOK-ORDER.md
 */

'use strict';

const fs = require('fs');
const path = require('path');

// --- State helpers (shared across hooks) ---
const stateLib = require('./lib/state-paths');

// JST = UTC+9
const JST_OFFSET_MS = 9 * 60 * 60 * 1000;

// --- Category 1: FWD (forward-seeking confirmation) ---
// Matches interrogative / permission-seeking forms.
// Statements ending in 「進めます。」「次のフェーズに進みます。」are COMPLETION reports and must NOT match.
const FORWARD_RE =
  /進めます(?:か|？|\?)|よろしいですか|次に?進み(?:ます)?(?:か|？|\?)|次の?フェーズに進み(?:ます)?(?:か|？|\?)|進めてもよろしい|実行してもよろしい|続行してもよろしい|shall I proceed|should I continue|proceed to phase|ready to continue\?|問題(?:が)?なければ[^。]*進め|確認できたら[^。]*進め|OK[\s　]*で?あれば[^。]*進め|確認後[にで][^。]*進め|ご確認の上[^。]*(?:進め|マージ|merge)|if\s+no\s+issues[^.]*proceed|once\s+confirmed[^.]*(?:proceed|merge)|after\s+(?:you\s+)?verify[^.]*proceed/i;

// --- Category 2: BWD (backward-seeking / deferral to user) ---
// Matches patterns that defer judgment back to the user instead of making the call.
const BACKWARD_RE =
  /ここで止めて|一旦.*合意|Plan\s*Mode\s*で改めて|user[\s　]*判断を仰ぎ|ご判断ください|user[\s　]*が選/i;

// --- Category 3: MC (multi-choice offering) ---
// Conservative design: requires ALL THREE elements simultaneously:
//   "(1)" AND "(2)" AND one of the trailing choice-phrases.
// Lone "(1)" or "どうしますか" alone will NOT hit this pattern.
// Wrapping all alternatives in (?:...) ensures the "(1)+(2)" prefix applies to every branch.
const MULTICHOICE_RE =
  /\(1\)[\s\S]{1,200}\(2\)[\s\S]{0,500}(?:どうしますか|どちらにしますか|どれを(?:選|お?選び)|お任せします|let me know which)|確認したい[^。]{0,30}(?:設計判断|判断|事項|点)[\s\S]{0,500}?(?:採用[しさ]?[てる]?(?:続行|進め)|決定的[にで][^。]{0,15}dispatch|(?:自[己分][決判]断|自己決定)[しさ]?[てた]?(?:進め|続行))/i;

// --- SCOPE_CUT_RE: warning-only, block 対象ではない ---
// Detects when an agent instructs Delivery Manager to skip merge/cleanup.
// Checked independently — runs regardless of the 3-category detection.
const SCOPE_CUT_RE =
  /Do NOT merge|leave.*it.*open|for user review|skip.*merge|merge.*しない|close.*PR.*manually|省略.*merge/i;

// --- Dry-run mode (対策 4) ---
// When CONF_LEAK_DRY_RUN=1, emit warning only — never output block JSON.
const DRY_RUN = process.env.CONF_LEAK_DRY_RUN === '1';

const ACTIVITY_LOG = path.join(process.env.HOME, '.claude', 'activity.log');

const MAX_STDIN = 2 * 1024 * 1024;
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

// --- Session-scoped block counter (対策 1: same-session 2-block cap) ---
// State file: ~/.claude/state/conf-leak-block-count-<sessionId> (single integer)
// Fallback: /tmp/conf-leak-block-count-<sessionId> (旧 path — migration 互換)

function loadBlockCount(sessionId) {
  const raw = stateLib.readStateWithFallback('conf-leak-block-count', sessionId);
  if (raw === null) return 0;
  const n = parseInt(raw.trim(), 10);
  return Number.isFinite(n) && n >= 0 ? n : 0;
}

function incrementBlockCount(sessionId) {
  const next = loadBlockCount(sessionId) + 1;
  stateLib.writeStateAtomic('conf-leak-block-count', sessionId, String(next));
  return next;
}

// --- Block flag for completion-gate.js ---
// Creates ~/.claude/state/conf-leak-blocked-<sessionId> as an empty file when a block fires.
function setBlockedFlag(sessionId) {
  stateLib.writeStateAtomic('conf-leak-blocked', sessionId, '');
}

function run() {
  let input;
  try {
    input = JSON.parse(data);
  } catch {
    process.exit(0);
  }

  const sessionId = (input.session_id || '').trim();

  // If no session_id we cannot check the flag — skip
  if (!sessionId) {
    process.exit(0);
  }

  // Guard against path traversal: session_id must be a safe identifier
  if (!/^[\w.-]+$/.test(sessionId)) {
    process.exit(0);
  }

  // Check plan-approved flag — stack-aware (any plan on stack approved triggers detection)
  const stack = stateLib.readPlanStack(sessionId);
  let approved = null;
  if (Array.isArray(stack) && stack.length > 0) {
    // Check any plan on stack
    for (const pid of stack) {
      const s = stateLib.statPlanStateWithLegacyFallback('plan-approved', sessionId, pid);
      if (s) { approved = s; break; }
    }
  } else {
    approved = stateLib.statStateWithFallback('plan-approved', sessionId);
  }
  if (approved === null) {
    // No plan approved in this session — nothing to enforce
    process.exit(0);
  }

  // Prefer last_assistant_message from payload (fastest path)
  const message = (input.last_assistant_message || '').toString();

  if (!message) {
    process.exit(0);
  }

  // --- SCOPE_CUT_RE: warning-only, independent of block logic ---
  // NOTE: SCOPE_CUT_RE is warning only — it is NOT a block target.
  const scopeMatch = SCOPE_CUT_RE.exec(message);
  if (scopeMatch) {
    const snippet = buildSnippet(message, scopeMatch.index, 80);
    process.stderr.write(`⚠️ Delegate scope-cut detected: "${snippet}"\n`);
    try {
      const nowJst = new Date(Date.now() + JST_OFFSET_MS);
      const ts = nowJst.toISOString().replace('T', ' ').slice(0, 19);
      const logLine = `[DELEGATE-SCOPE-CUT] ${ts} | session=${sessionId} | snippet="${snippet}"\n`;
      const fd1 = fs.openSync(ACTIVITY_LOG, 'a', 0o600);
      try { fs.writeSync(fd1, logLine); } finally { fs.closeSync(fd1); }
    } catch { /* fail silently */ }
    // NOTE: no process.exit(0) here — continue to check 3-category patterns below
  }

  // --- 3-category detection (data-driven) ---
  const CATEGORIES = [
    { key: 'FWD', re: FORWARD_RE,      tag: '[CONF-LEAK-FWD]' },
    { key: 'BWD', re: BACKWARD_RE,     tag: '[CONF-LEAK-BWD]' },
    { key: 'MC',  re: MULTICHOICE_RE,  tag: '[CONF-LEAK-MC]'  },
  ];

  let category = null;
  let match = null;
  for (const c of CATEGORIES) {
    const m = c.re.exec(message);
    if (m) {
      category = c;
      match = m;
      break;
    }
  }

  if (!category) {
    process.exit(0);
  }

  const snippet = buildSnippet(message, match.index, 80);
  const tag = category.tag;

  // Activity log is always written regardless of block/warn decision
  try {
    const nowJst = new Date(Date.now() + JST_OFFSET_MS);
    const ts = nowJst.toISOString().replace('T', ' ').slice(0, 19);
    const fd = fs.openSync(ACTIVITY_LOG, 'a', 0o600);
    try { fs.writeSync(fd, `${tag} ${ts} | session=${sessionId} | snippet="${snippet}"\n`); } finally { fs.closeSync(fd); }
  } catch { /* fail silently */ }

  const blockCount = loadBlockCount(sessionId);

  // 対策 1 (2-block cap) + 対策 4 (dry-run) determine whether to block
  const shouldBlock = !DRY_RUN && blockCount < 2;

  if (shouldBlock) {
    incrementBlockCount(sessionId);
    setBlockedFlag(sessionId);
    const reason = `Confirmation leak detected (${category.key}): "${snippet}". Plan is pre-authorized — make the judgment call yourself per Mid-execution Judgment Rules, append to Decision Log, and continue without asking.`;
    process.stdout.write(JSON.stringify({ decision: 'block', reason }) + '\n');
    process.stderr.write(`⛔ ${tag} Stop blocked (count=${blockCount + 1}/2): "${snippet}"\n`);
    process.exit(0);
  } else {
    // 3rd+ attempt or dry-run — warning only
    const why = DRY_RUN ? 'dry-run' : `over limit (${blockCount}/2)`;
    process.stderr.write(`⚠️ ${tag} Confirmation leak detected (${why}): "${snippet}"\n`);
    process.exit(0);
  }
}

/**
 * Returns a substring of `text` of at most `maxLen` characters centred on `matchIndex`.
 * Sanitizes control characters and log-line prefix patterns.
 */
function buildSnippet(text, matchIndex, maxLen) {
  const half = Math.floor(maxLen / 2);
  const start = Math.max(0, matchIndex - half);
  const end = Math.min(text.length, start + maxLen);
  let snippet = text.slice(start, end)
    .replace(/[\r\n\u2028\u2029]/g, ' ')      // CR / LF / LS / PS -> space
    .replace(/\[CONF-LEAK-/g, '[(CONF-LEAK-')   // tag prefix escape (log 行偽装防止)
    .replace(/\[DELEGATE-SCOPE-CUT/g, '[(DELEGATE-SCOPE-CUT');
  if (start > 0) snippet = '…' + snippet;
  if (end < text.length) snippet = snippet + '…';
  return snippet;
}
