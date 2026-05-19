# spec-default.md — 運用ガイド

> このファイルは `spec-default.md` template の運用ガイド。template 本体には載せず、c2 が `/spec` を打った時に section 充填の参考にする。

## title 命名規則

- **言語**: 日本語推奨 (短いセンテンス 15-40 字)
- **形式**: 動詞 + 目的語 (例: 「Spec ファイルを md と Notion 運用に移行」)
- **避けるべき**: 半角スラッシュ `/` / 改行 / `spec-` prefix (DB 内で冗長)

## 全 section の説明

### §1 Context

問題・背景を 3-10 行で記述。なぜ今これをやるか、現状の何が壊れているか。

### §2 Glossary

主要用語 5 件固定。`<term>` — `<1 行定義>` 形式。新人 c2 / the user が読んで迷わない最小集合。

### §3 Goal

達成すべき最終状態。1-3 sentences。Acceptance Scenarios (§6) の親仮説。

### §4 Big Picture

Goal 達成後の全体像。**User action 単位 sub-diagram** で sequenceDiagram 必須 (flowchart 不可)。1 sub-diagram = 1 user action の流れ。複雑な flow は 3-5 個に分割。

### §5 Non-Goal

明示的に対象外とすること。OoS との違いは「Non-Goal はあえてやらない判断、OoS は別 Spec/PR」。

### §6 Acceptance Scenarios

Gherkin 形式 (Given / When / Then)。**Scenario ごとに code block 分割**。検証可能・自動 or 半自動 (manual sanity) を明示。

### §7 Devil's Advocate

6 sub-question:
1. 前提の正しさ (観点別展開: 必要)
2. 代替案 (観点別展開: 統合 OK)
3. リスク・副作用 (観点別展開: 必要)
4. ユーザー価値 (観点別展開: 必要)
5. test 戦略 (観点別展開: 統合 OK)
6. 既存実装の削除候補 (観点別展開: 統合 OK)

「観点別展開: 必要」の場合は security / architect / code / pdm / ceo / ops / dx の関連観点で個別に表形式で記述。

### §8 Design

Phase ごとに sequenceDiagram sub-diagram (flowchart 不可)。Phase 構成、各 step の責務、関連 file path を明示。

### §9 Risks & Mitigations

HIGH / MED / LOW で分類。各 risk は「発生条件 / 対策 / 検証 / ロールバック」の 4 項目を埋める。

### §10 Out of Scope

Backlog Discipline (a) 現ゴール独立 + (b) ユーザー意図ブロックしない の両方を満たす項目のみ。

### §11 関連 Plan の Notion URL

Plan を起こした後、その Notion URL (もしくは plan file path) をここに貼る。Spec/Plan の双方向リンク。

### §12 Backlog 候補

Plan §📋 へ転記される候補。Spec 段階では仮列挙、Plan 確定時に最終化。

### §13 Rule Reduction Candidates

規律追加 PR のみ必須。norm N-4 で要求される削減候補を 1 件以上明示。

## sequenceDiagram 分割ルール

- 1 sub-diagram = 1 user action / 1 phase
- 5+ actor が混在する場合は分割を検討
- label の `as` 句は special char (括弧 / `<br/>` / `&lt;` 等) を avoid、必要なら double quote 化
- 全角カッコは半角に統一

## DA 観点別展開ルール

§7.1 / §7.3 / §7.4 で「観点別展開: 必要」と書かれた場合:
- security / architect / code-reviewer / pdm / ceo / ops / dx-reviewer の関連観点 (全 7 通り全部使う必要はない、関連するもののみ)
- 表形式: 観点 / 判定 (Pro/Con/Con-mitigated/N/A) / 根拠 / 対策の有無

## 関連 Plan の Notion URL 貼り付けルール

§11 に Notion URL or plan file path を貼る。Plan file 冒頭にも対応 Spec の Notion URL を必ず貼る (双方向リンク)。
