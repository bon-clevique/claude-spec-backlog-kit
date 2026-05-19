# claude-spec-backlog-kit

Spec + Backlog 運用のための Claude Code 設定ファイル一式。

zenn 記事「AI に実装を任せたら、自分の仕事は『何を作るか』と『やらないこと』だけになった」の参照実装として公開している kit です。

> **Mirror repo です**: このディレクトリは `bon-clevique` の `~/.claude/` から、ホワイトリスト形式 + 自動 sanitize で export された **読み取り側 mirror** です。本 repo に直接 PR を送っても本体には反映されません。提案やフィードバックは [issue](../../issues) へお願いします。

> **初見の方は [USAGE.md](./USAGE.md) を先に**。最短 15-30 分で全体像と取り入れ方の選択肢を案内します。

## 何が含まれているか

| Path | 役割 |
|---|---|
| `skills/spec/` | `/spec` skill。会話文脈 / 自然言語 / md / Notion URL から Spec を起こし Notion DB に push |
| `skills/backlog/` | `/backlog` skill。ULID + 6-field schema の Backlog 管理 (list / pick / done) |
| `scripts/hooks/` | Plan File Lifecycle / Confirmation Leak Detector / Completion Gate / Plan Enforce などの hook 群 |
| `scripts/notion/` | Notion API v2 (data_source_id) の薄い REST wrapper (MCP は使わない) |
| `scripts/lib/` | 共通 lib: `redact.sh` (sanitize), `mini-da-template.sh` (Out-of-Plan 判定), `plan-pr-target-resolver.sh` (case-a/b/c 判定) |
| `scripts/create-draft-pr.sh` | Plan 承認直後の Draft PR 自動生成 |
| `scripts/sync-public-mirror.sh` | 本 kit を ~/.claude/ から sanitize 同期するスクリプト本体 |
| `templates/` | Plan / PR / Spec / Delivery Manager prompt / Nested team 各 template |
| `rules/common/` | `workflow-enforcement.md` (Layer 2 規律 65 行版) + `coding-standards.md` |
| `agents/` | Spec review の 7 観点 (Security / PdM / CEO / CTO / TA / Ops / DX) + Planner / Mini-DA / Backlog Task Manager |
| `BACKLOG.md` / `CLAUDE.md` | kit の SoT ドキュメント (index 形式) |
| `reference/notion-databases.md` | Notion DB スキーマ (Claude Code Specs / GitHub PR sync 等) |
| `settings.json` | Claude Code 設定 (permissions / hooks / effortLevel 等) |

## 使い方

そのまま自分の `~/.claude/` に丸ごと置き換えるのは **推奨しません**。代わりに次のステップを推奨します。

1. zenn 記事 (前編 / 後編) で全体像と「なぜそうしたか」を掴む
2. 興味のある部分から見る
   - **Spec を Notion に起こす運用** → `skills/spec/SKILL.md` + `scripts/notion/`
   - **Backlog を ULID で管理する運用** → `skills/backlog/SKILL.md` + `BACKLOG.md`
   - **Plan File Lifecycle** → `scripts/hooks/plan-*` + `rules/common/workflow-enforcement.md`
   - **規律設計 (1247行→2行)** → `rules/common/workflow-enforcement.md` (Layer 2 のみ)
   - **Spec review の 7 観点 agent** → `agents/{security,pdm,ceo,architect,code,ops,dx}-reviewer.md`
3. 必要な部分だけを自分の `~/.claude/` に取り込む。先に依存関係を確認: `~/.claude/scripts/lib/` 配下の lib が hook から参照されている等
4. `settings.json` の hook 参照 path / permissions を自分の環境に合わせて書き換える
5. `scripts/notion/` を使う場合は `NOTION_API_KEY` を `.zshenv` 等に設定 + Notion DB を作成 (`scripts/notion/create_db.py` でテンプレ生成可)

## 前提環境

- Claude Code v2.1.122+ (`@`-mention typeahead, Hook system, plan-current-recorder.js 等)
- macOS (BSD sed / Kitty / Xcode を想定。Linux でも `sed -E` 部分は動くはず)
- Notion ワークスペース + API key (Spec の SoT を Notion に置く運用を採用する場合)
- gh CLI (Delivery Manager の `gh pr create` / `gh pr ready` で使用)

## 関連記事

- 前編: [AI に実装を任せたら、自分の仕事は『何を作るか』と『やらないこと』だけになった](#) ← (公開後 URL 差し替え)
- 後編: [ルール 1,247 行を 2 行に削るまで——AI 開発で「規律累積」と戦った 1 週間](#) ← (公開後 URL 差し替え)

## 注意

- 本 repo 内の secret / API key 類はすべて `<REDACTED-*>` 等のプレースホルダに置換済
- Notion DB の `data_source_id` も `<YOUR_DATA_SOURCE_ID>` に置換済
- 個人情報 (実 path / メール / 個人名等) は `<your-github-user>` `$HOME/` `the user` 等に正規化済
- 自分で使う前に、それぞれの環境固有の値に書き換える必要があります

## sanitize / mirror の仕組み

本 kit は `~/.claude/scripts/sync-public-mirror.sh` で本体 `~/.claude/` から差分同期しています。

- **whitelist 形式**: `scripts/sync-public-mirror.sh` の `WHITELIST` 配列に列挙された 61 ファイルのみ同期 (それ以外は絶対に kit に出ない)
- **自動 sanitize**: `scripts/lib/redact.sh` の `redact_content` 関数で全コピー時に sed で credential / 個人情報を `<REDACTED-*>` / `<your-*>` に置換
- **verify_clean**: 同 lib の `verify_clean` 関数で漏れ検出。`--init` / `--verify` で leak が検出された場合は exit 1 (rollback)
- **self-test**: `bash scripts/lib/redact.sh --self-test` で 9 cases の sanitize 動作確認 (CI 等に組込み可)

## ライセンス

MIT (LICENSE 参照)
