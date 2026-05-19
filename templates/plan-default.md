# Plan Template (default — 2026-05-13 compressed)

> 新規 plan は最初の `EnterPlanMode` で harness が提示した `~/.claude/plans/<slug>.md` path にのみ Write する。改訂は同 path 上書き。詳細 → `workflow-enforcement.md` §Plan File Lifecycle Protocol。

# Plan: <Feature Name>

> **重要**: 設計詳細 (Context / Goal / Non-Goal / Acceptance Scenarios / Devil's Advocate / Design / Risks) は対応 Spec **`docs/specs/<slug>.html`** を参照。本 Plan は実装作業 checklist + Decision Log + Delivery に特化。
>
> **実行ルール**: 承認後は全 step を end-to-end で実行。停止条件は `workflow-enforcement.md` §Stop Whitelist の 3 ケース (本 plan §4 経由)。

## 0. Pre-flight

- [ ] 対応 Spec (`docs/specs/<slug>.html`) を Read し goal / acceptance / DA / risks を内在化

## 2. Implementation Steps

### Phase <N>: <Phase 名>

<!-- agent-required: <agent-type> -->

- [ ] **Step N**: <step 名>
  - File: `<path>`
  - 変更内容: <具体的な what>
  - **Step DoD**: <verifiable closure criterion 1-3 行>

**Phase <N> DoD** — required (Phase 完了の判定条件):
- [ ] <criterion 1>
- [ ] <criterion 2>

## 3. Files

| # | Path | 種別 (new/edit/delete) | Phase |
|---|---|---|---|

## 4. Mid-execution Judgment Rules

詳細 → `~/.claude/CLAUDE.md` §Stop Whitelist & Mid-execution Judgment Rules (本文は `workflow-enforcement.md` §Stop Whitelist & Mid-execution Judgment Rules SoT)

**停止条件 (Stop Whitelist) の 3 ケース**:
1. **External blocker** (技術的に実行不能、user judgment 待ち含む)
2. **Plan 未記載 + irreversible**
3. **User explicit interrupt**

それ以外で停止したら norm 違反。詳細は上記参照リンク先で確認。

## 7. Verification

### 7.1 自動 (blocking)
- <test command>

### 7.2 半自動 (non-blocking)
- Manual: <NOT BLOCKING>
- 必要なら **BLOCKING** Manual: <人手 gate>

## 8. Agent Team

| Phase | Step | 担当 | Model / effort | 理由 |
|---|---|---|---|---|

## 9. Decision Log (required — 空のまま提出禁止)

> 実装中の判断記録。sub-agent 差異 / Mid-execution dispatch / 仮説修正 のいずれかに該当する事象が発生したら即記入。空のまま完了報告した場合は norm 違反。
> Format: `[YYYY-MM-DD HH:MM] Phase X step Y / 事象 / 判断 / 根拠`

## 10. Delivery

> **必須 norm (2026-05-14)**: Delivery は **必ず Agent tool で Delivery Manager sub-agent に委譲する**。main session が直接 `git push` / `gh pr merge` 等を実行してはならない。委譲構文: `Agent({subagent_type: 'general-purpose', name: 'Delivery Manager', prompt: '<plan §10 全文 + 逐語引用ルール>'})`。理由: main session の context 圧迫回避 + Spec/Plan approval state の保全 + 規律違反検出が user レビュー時に容易。

> 逐語引用 boilerplate: Delivery Manager 委譲時、本セクションを copy-paste (`delivery.md` §逐語引用ルール 参照)。

<Pre-PR Checks → Push & PR → Remote CI → Conflict Resolution → Merge & Cleanup の各 step を明示>

> **Out of Scope は対応 Spec §8 を参照** (`docs/specs/<slug>.html` の `<h2>8. Out of Scope</h2>`)。Backlog Discipline (a)+(b) 両 yes 時のみ OoS 化、それ以外は本 PR fix (詳細 → workflow-enforcement.md §PR review 指摘の Backlog Discipline)。
