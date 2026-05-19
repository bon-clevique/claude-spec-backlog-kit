# PR: <title>

> 対応 Spec: <Notion URL or `docs/specs/<slug>.html` path>
> 対応 Plan: <plan file path or in-line summary if Plan-less>

## Summary

- <1-3 bullets で改修内容要約>
- <なぜ今この変更を入れるかの 1 行>
- <影響範囲の 1 行>

## Changes

| # | Path | 種別 | Phase |
|---|------|------|-------|
| 1 | `<path/to/file>` | new / edit / delete | <Phase 番号 or 単発> |
| 2 | ... | ... | ... |

## Test Plan

- **Local CI**: <command + 結果 or N/A>
- **Auto verification** (blocking): <hook fires / lint pass / unit test 等、確定的に通っているもの>
- **Manual sanity** (non-blocking): <UI 起動確認 / 物理デバイス / 課金確認等。default で merge を block しない。block したい場合は明示的に `**BLOCKING**` を付ける>

## Reviewer Reports (7 perspectives)

> 各 reviewer agent の出力を逐語的に貼り付ける。要約や抽出は禁止 (元発言の意図を歪める)。

### Security (security-reviewer)

<security-reviewer agent output 逐語添付>

### Architecture / CTO (architect)

<architect agent output 逐語添付>

### TA / Test Architecture (code-reviewer)

<code-reviewer agent output 逐語添付>

### PdM (pdm-reviewer)

<pdm-reviewer agent output 逐語添付>

### CEO (ceo-reviewer)

<ceo-reviewer agent output 逐語添付>

### Ops (ops-reviewer)

<ops-reviewer agent output 逐語添付>

### DX (dx-reviewer)

<dx-reviewer agent output 逐語添付>

## Review Status Disposition

> 各 reviewer 指摘について処理状況を記入。`[x]` = 対応済 / `[~]` = 部分対応 / `[ ]` = 未対応 (要 ADR 化または OoS 確認)。
>
> 未対応 (`[ ]`) 指摘は本 PR の `## 📋 Backlog 候補` table に登録するか、対応 Spec の §8 Out of Scope に明示すること。サイレントスコープ削減禁止。

- [ ] (Security) <指摘 1 要旨>: <処理内容 or OoS 理由>
- [ ] (Architect) <指摘 1 要旨>: <処理内容 or OoS 理由>
- [ ] (TA) <指摘 1 要旨>: <処理内容 or OoS 理由>
- [ ] (PdM) <指摘 1 要旨>: <処理内容 or OoS 理由>
- [ ] (CEO) <指摘 1 要旨>: <処理内容 or OoS 理由>
- [ ] (Ops) <指摘 1 要旨>: <処理内容 or OoS 理由>
- [ ] (DX) <指摘 1 要旨>: <処理内容 or OoS 理由>

## Decision Log

> plan の §9 Decision Log を逐語的にコピーする (memory/要約からの再構成は禁止)。
> Plan-less の単発 PR では本 section を省略可。

<plan の §Decision Log 逐語コピー>

## Out of Scope (本 PR で扱わない)

> 対応 Spec の §8 OoS から本 PR 関連項目を抜粋。または PR 内で見送り判断した項目を追記。

- <項目 1>: <理由>
- <項目 2>: <理由>

## 📋 Backlog 候補

> Plan file の `## 📋 Backlog 候補` (同名 section) と一致する内容を記載。PR merge 時に `plan-archive-on-merge.sh::import_backlog_section` が plan §📋 を読み、`add-internal.sh` 経由で `~/.claude/backlog/<project-slug>/<ulid>-<slug>.md` を BACKLOG.md v2 schema (id/slug/project/status/created/updated) で生成する。
> 完了報告 turn での自動 register は PR #40 で廃止 (`backlog-auto-extractor.sh` 削除)。
> 詳細 schema: `~/.claude/BACKLOG.md` §6。

| title | description | project-slug | defer-period |
|-------|-------------|--------------|--------------|
| <title> | <why 1 行 = description> | <`_claude-meta` or project slug> | `next-session` / `next-week` / `eventual` |

## 🔴 ユーザー必須操作

> c2 が代行不可で、ユーザーが手動で実行する必要がある操作。Backlog table とは別の H2 section として明示。silent scope cut 防止のため backlog に混入させない。

- <操作 1: 例 — Apple Developer Portal で certificate 更新>
- <操作 2: 例 — Notion DB の property 設定変更>

## 🔁 recap

> Spec/Plan 経由 PR の場合に必須。Stop hook (`spec-recap-extractor.sh`) が parse して対応 Spec page の `recap` property に push する。
> Plan-less 単発 PR では省略可。

Goal: <1 文で本タスクの目的>
完了: <達成内容と PR/commit リンク>
次の確認: <次セッション以降で確認すべき事項>
