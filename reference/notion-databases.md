# Notion Database Details

## API info
- **Version**: 2026-03-11
- **Change**: `database_id` → migrated to `data_source_id`
- **Reference**: https://developers.notion.com/guides/get-started/upgrade-guide-2026-03-11

## Database list

### 1. Input Warehouse
- **Purpose**: Output storage
- **database_id**: `<UUID>`
- **data_source_id**: `<UUID>`

### 2. Bon Task
- **Purpose**: Task management
- **database_id**: `<UUID>`
- **data_source_id**: `<UUID>`
- **Default setting**: Status = "To Do"

### 3. Literature Notes
- **Purpose**: Project linking
- **database_id**: `<UUID>`
- **data_source_id**: `<UUID>`

### 4. Product Docs
- **Purpose**: Product documentation (PRD, Design, Spec, ADR, etc.)
- **data_source_id**: `<UUID>`
- **Guide**: `~/.claude/reference/product-docs-guide.md`

### 5. Products
- **Purpose**: Product master (BarNoR, bonvue, etc.)
- **data_source_id**: `<UUID>`

### 6. Dev Plan
- **Purpose**: c2 plan history (migrated from `~/.claude/plans/`)
- **data_source_id**: `<UUID>`

### 7. GitHub プルリクエスト (sync DB)

- **Purpose**: GitHub PR 一覧 (Notion 公式 GitHub integration による自動 sync)
- **data_source_id**: `<UUID>` (external collection、public API では `pages.create` 不可)
- **連携 path (正規)**: PR description / commit message に `closes <unique_id>` (例: `closes CC-10`) を含めると、Notion 公式 GitHub-Notion sync が自動で:
  1. PR row を本 DB に push
  2. 対応 Spec page (Unique ID で識別) の `GitHub PR` relation property に PR page を双方向 link
  3. PR merge 時に Spec page の ステータス を自動更新 (close / fix / resolve キーワード時)
- **手動連携 (deprecated, 2026-05-17 PR #40 で確定)**: Notion AI が誘導する以下 3 手法は **全て public API で reject**:
  1. relation property に URL 文字列を投入: `400 validation_error "GitHub PR is expected to be relation"`
  2. external collection への `pages.create`: `400 "Child of an external user defined external collection instance is not an external object instance"`
  3. `connections.notion.*` API: これは Notion 内部 button/automation の scripting API で **public API には存在しない**
- **唯一の正規 path** = magic word (`closes <unique_id>`)。`~/.claude/scripts/create-draft-pr.sh` が PR body 先頭に自動付与する (PR #41 で実装)
- **関連 state file** (Bon が直接編集する想定なし、自動管理):
  - `~/.claude/state/spec-page-<title>` — Notion page_id (UUID)。`spec-create.sh` で書出、`spec-finalize.sh` / `plan-archive-on-merge.sh` で rm
  - `~/.claude/state/spec-unique-id-<title>` — Unique ID 文字列 (例: `CC-10`)。`spec-create.sh` で書出 (`md_to_notion.py` の create_page() return から取得)、`spec-finalize.sh` / `plan-archive-on-merge.sh` で rm。不在時は `create-draft-pr.sh` が Notion API `pages.retrieve` で backfill
  - **Recovery path**: 両 state file 不在 + Notion API 失敗時は magic word なし PR が作成される (PR は通る)。手動 recovery は Bon が PR body 先頭に `closes <unique_id>` を追加 (Notion sync が trigger される)
- **関連 script**:
  - `~/.claude/scripts/create-draft-pr.sh` (magic word 自動挿入)
  - `~/.claude/skills/spec/scripts/spec-create.sh` (state file 書出)
- **Incident runbook**:
  - magic word が間違った Spec に link した: Notion UI で PR page の `Spec` relation を手動 edit + `~/.claude/state/spec-unique-id-<title>` の中身を確認
  - Notion sync が 60 秒経っても link しない: `~/.claude/activity.log` から `[MAGIC-WORD-OK]` を grep、対応 prefix が PR body 先頭にあるか確認
  - magic word 自動付与を一時停止したい: `SPEC_MAGIC_WORD_OFF=1` env var を export してから `create-draft-pr.sh` 実行
  - state file 不在 + Notion API 失敗時: 手動で PR body 先頭に `closes <unique_id>` を追加 (Notion sync が trigger される)、または対応する `~/.claude/state/spec-unique-id-<title>` を手動作成

## Environment variable mapping

| Variable | Value | Purpose |
|---|---|---|
| `NOTION_API_KEY` | `.zshenv` | Shared across all skills |
| `NOTION_INPUT_WAREHOUSE_DATA_SOURCE_ID` | `<UUID>` | notion-add-note, create-test-db |
| `NOTION_TOKEN` | in plist | NotionSync (for notion-client SDK) |
| `NOTION_DATABASE_ID` | `<UUID>` | NotionSync |

## Storage rules
- **Chats within a Claude project**: Link to Literature Notes
- **Chats outside a project**: No Literature Notes link
- **Default task Status**: "To Do"
