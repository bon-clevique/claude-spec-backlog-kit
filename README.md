# claude-spec-backlog-kit

Spec + Backlog 運用のための Claude Code 設定ファイル一式。

zenn 記事「AI に実装を任せたら、自分の仕事は『何を作るか』と『やらないこと』だけになった」
の参照実装として公開している kit。

## 何が含まれているか

- **skills/spec/** — `/spec` skill。会話文脈から Notion DB に Spec ページを起こす
- **skills/backlog/** — `/backlog` skill。やらないことを ULID + 6-field schema で管理
- **scripts/hooks/** — Plan File Lifecycle / Confirmation Leak / Completion Gate 等の hook
- **scripts/notion/** — Notion API v2 SDK の薄い wrapper (REST 直叩き、MCP 不使用)
- **scripts/lib/** — 共通 lib (`redact.sh` で sanitize、`mini-da-template.sh` で Out-of-Plan 判定 等)
- **templates/** — Plan / PR / Spec template
- **rules/common/** — workflow-enforcement (65 行版) + coding-standards
- **agents/** — Spec review の 7 観点 (Security / PdM / CEO / CTO / TA / Ops / DX) + Planner / Mini-DA / Backlog Task Manager
- **BACKLOG.md** / **CLAUDE.md** — kit の SoT ドキュメント
- **reference/notion-databases.md** — Notion DB スキーマ
- **settings.json** — Claude Code 設定 (permissions / hooks / effortLevel 等)

## 使い方

このディレクトリは、自分の `~/.claude/` から sanitize して export された **mirror** です。
そのまま自分の `~/.claude/` に置き換えるのは推奨しません。代わりに:

1. zenn 記事を読んで全体像を掴む
2. 各 skill / agent の SKILL.md を読み、自分の運用に合うものを選ぶ
3. 必要な部分だけを自分の `~/.claude/` に取り込む

## 関連記事

- [AI に実装を任せたら、自分の仕事は『何を作るか』と『やらないこと』だけになった (前編)](https://zenn.dev/clevique) — 現状の Spec + Backlog 運用
- [ルール1247行→2行にした話。AIに本当に任せるための規律設計術 (後編)](https://zenn.dev/clevique) — そこに至るまでの 1 週間の悪戦苦闘

(blog 公開時に URL を確定)

## 本体との関係

このリポジトリは `<your-github-user>` の `~/.claude/` から、ホワイトリスト形式 + 自動 sanitize で
export された **読み取り側 mirror** です。本 repo に直接 PR を送っても本体には反映されません。

提案やフィードバックは [issue](../../issues) でお願いします。

## ライセンス

MIT (LICENSE 参照)

## 注意

- 本 repo 内の secret / API key 類はすべて `<REDACTED-*>` 等のプレースホルダに置換済
- Notion DB の `data_source_id` も `<YOUR_DATA_SOURCE_ID>` に置換済
- 自分で使う前に、それぞれの環境固有の値に書き換える必要があります
