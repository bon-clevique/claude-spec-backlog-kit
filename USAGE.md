# USAGE.md — 初見者向けガイド

`claude-spec-backlog-kit` は **何を作るか (Spec)** と **やらないこと (Backlog)** を中心に Claude Code を運用する仕組みのスナップショットです。本ガイドは「最初に何を読むか」「自分の環境に取り入れるならどこから手を付けるか」の道案内です。

## 1. 全体の地図 (5 分で把握)

このリポジトリは以下の層に分かれています。

| 層 | path | 役割 | 初見者は読むべき? |
|---|---|---|---|
| **Spec layer** | `skills/spec/` | 設計を Notion に起こす skill | ✅ 最初に読む |
| **Backlog layer** | `skills/backlog/` + `BACKLOG.md` | やらないことを ULID で管理 | ✅ 最初に読む |
| **Discipline layer** | `rules/common/workflow-enforcement.md` + `CLAUDE.md` | 規律 (Layer 1/2/3) の宣言 | ⭕ 概念だけ掴む |
| **Hook layer** | `scripts/hooks/` | Plan File Lifecycle / Confirmation Leak 等 | ⏸ 必要になったら |
| **Agent layer** | `agents/` | Spec review の 7 観点 + Planner / Mini-DA | ⏸ 必要になったら |
| **Infra layer** | `scripts/notion/`, `scripts/lib/`, `templates/` | API / lib / template | ⏸ 必要になったら |

## 2. 最短の理解パス (15-30 分)

### Step 1: zenn 記事を読む
- 前編: AI に実装を任せたら、自分の仕事は『何を作るか』と『やらないこと』だけになった
- 後編: ルール 1,247 行を 2 行に削るまで——AI 開発で「規律累積」と戦った 1 週間

### Step 2: Spec と Backlog の SKILL.md を読む
- `skills/spec/SKILL.md` — 4 起動 Mode (M1〜M4) と Notion sync の仕組み
- `skills/backlog/SKILL.md` — 6-field schema / 3 status / 3 commands

### Step 3: 規律の見出しだけ眺める
- `rules/common/workflow-enforcement.md` — Layer 2 (R-α / R-β) のみで本体は **65 行**

## 3. 取り入れ方の選択肢

### 選択肢 A: Spec だけ採用 (最も低リスク)

Notion を SoT にする運用だけ採用する。Backlog や規律は自分の既存運用を保つ。

必要なファイル:
- `skills/spec/SKILL.md` + `skills/spec/scripts/*.sh`
- `skills/spec/templates/spec-default.md`
- `scripts/notion/{read_page,create_db,notion_wrapper}.py`
- 環境変数: `NOTION_API_KEY` (Notion API key)
- Notion DB: 「Claude Code Specs」を自分のワークスペースに作成 (`scripts/notion/create_db.py` でテンプレ生成可)

### 選択肢 B: Spec + Backlog 採用 (中リスク)

Spec の Notion 化 + Backlog の ULID 管理を採用。Plan File Lifecycle や Hook は自分の既存 hook で補完。

追加で必要:
- `skills/backlog/` 全部
- `BACKLOG.md` (運用規約)
- `scripts/lib/` (依存 lib)

### 選択肢 C: 全部採用 (高リスク・要 fork)

`~/.claude/` をまるごと差し替える。**非推奨**。代わりに以下を推奨します。

1. 本 kit を fork
2. 自分の既存 `~/.claude/` をブランチで残す
3. 1 layer ずつ移行 (Spec → Backlog → Discipline → Hook → Agent)
4. 各 layer 移行後、自分の運用 1 週間で破綻しないか観察してから次へ

## 4. 必須の前提環境

| 項目 | 推奨バージョン | 用途 |
|---|---|---|
| Claude Code | v2.1.122+ | hook / skill / `@`-mention 等 |
| macOS or Linux | BSD/GNU sed | `redact.sh` / `frontmatter-*.sh` 等 |
| bash | 5.x | hook 群、skill scripts |
| Python | 3.10+ | `scripts/notion/*.py` (Spec sync) |
| gh CLI | latest | Delivery Manager の PR 操作 |
| Notion API key | — | Spec の SoT 化 (Spec 採用時のみ) |

## 5. 環境構築の流れ (Spec layer 採用前提)

```bash
# 1. kit を fork してローカルに clone
gh repo fork bon-clevique/claude-spec-backlog-kit --clone
cd claude-spec-backlog-kit

# 2. 自分の ~/.claude/ にどこから取り込むか決める
ls skills/spec/ scripts/notion/ scripts/lib/

# 3. 必要なファイルを ~/.claude/ にコピー (例: Spec layer のみ)
mkdir -p ~/.claude/skills/spec/{scripts,templates}
cp skills/spec/SKILL.md ~/.claude/skills/spec/
cp skills/spec/scripts/*.sh ~/.claude/skills/spec/scripts/
cp skills/spec/scripts/*.py ~/.claude/skills/spec/scripts/
cp skills/spec/templates/*.md ~/.claude/skills/spec/templates/

mkdir -p ~/.claude/scripts/notion
cp scripts/notion/*.py ~/.claude/scripts/notion/

# 4. .zshenv に NOTION_API_KEY を追加
echo 'export NOTION_API_KEY=secret_...' >> ~/.zshenv
source ~/.zshenv

# 5. Notion DB「Claude Code Specs」を作成
python3 ~/.claude/scripts/notion/create_db.py --type specs
# → 出力された data_source_id を ~/.claude/reference/notion-databases.md に記録

# 6. 試す
# Claude Code セッションで:
#   /spec "簡単な設計を起こしたい"
```

## 6. 各 hook / script の責任 (リファレンス)

### Hooks (`scripts/hooks/`)

| Hook | Type | 役割 |
|---|---|---|
| `plan-current-recorder.js` | PostToolUse on Write | アクティブ plan path を state file に記録 |
| `plan-enforce.js` | PreToolUse | sub-agent / 主 session の plan 承認状態を enforce |
| `plan-approval-marker.js` | UserPromptSubmit | 「OK」「進めて」等の発話を承認マーカーとして記録 |
| `plan-archive-on-merge.sh` | PostBash on `gh pr merge` | merge 完了時に plan を archived/ へ移動、Out of Scope の backlog 候補を自動登録 |
| `completion-gate.js` | Stop | 完了報告が必要な状態で stop を試みた際にブロック |
| `confirmation-leak-detector.js` | Stop | 「どうしますか?」「進めてよろしいですか?」等の confirmation 発話を検出 (cap 2/session) |

### Scripts (`scripts/`)

| Script | 役割 |
|---|---|
| `create-draft-pr.sh` | Plan 承認直後に Draft PR を自動生成 (branch / commit / push / gh pr create / Notion update を 1 コマンドで) |
| `sync-public-mirror.sh` | 本 kit を `~/.claude/` から sanitize + whitelist 同期 (`--init` / `--verify` / `--dry-run` / default sync) |

### Lib (`scripts/lib/`)

| Lib | 提供関数 |
|---|---|
| `redact.sh` | `redact_content` (stdin → sanitize), `verify_clean DIR` (leak 検出), `--self-test` (9 cases) |
| `mini-da-template.sh` | Mini-DA agent 用 prompt template (Out-of-Plan 判定: proceed-light / propose-plan-mode / defer-to-backlog / split-task) |
| `plan-pr-target-resolver.sh` | cwd と変更ファイルから PR target repo を判定 (case-a/b/c/mixed) |
| `branch-from-plan.sh` | plan slug から `feature/<tail>` ブランチ名を生成 |
| `project-slug.sh` | cwd から project slug を解決 (backlog 配置先決定用) |

### Agents (`agents/`)

| Agent | 観点 |
|---|---|
| `security-reviewer.md` | OWASP / secret / SSRF / injection / unsafe crypto |
| `code-reviewer.md` | Test Architect 観点: quality / security / maintainability |
| `architect.md` | CTO 観点: architecture / scalability / technical decision |
| `pdm-reviewer.md` | PdM 観点: 顧客課題 / プロダクト価値 / UX / ユーザーセグメント |
| `ceo-reviewer.md` | CEO 観点: 収益性 / 市場 / 競合 / 事業継続性 / コスト |
| `ops-reviewer.md` | Ops 観点: 運用負担 / observability / incident response |
| `dx-reviewer.md` | DX 観点: c2 認知負荷 / 規律累積 / developer ergonomics |
| `planner.md` | Plan 設計 / 段階分割 |
| `mini-da.md` | Mid-execution の Out-of-Plan 判定 (3-line verdict) |
| `backlog-task-manager.md` | Backlog 自動登録 (oos / midexec / completion 3 mode) |

## 7. 注意 / 制約

- 本 kit は **mirror**。本 repo に PR を送っても自分の `~/.claude/` には反映されない (whitelist + sanitize 経由の片方向同期)
- `data_source_id` は `<YOUR_DATA_SOURCE_ID>` に置換済 → 自分の Notion DB のものに書き換え必須
- ホームディレクトリ path は `$HOME/` に正規化済 → 必要なら `/Users/<your-user>/` に書き戻し
- 個人名 (`Bon` 等) は `the user` / `<your-github-user>` に正規化済
- 規律 (`workflow-enforcement.md`) は **65 行版**。これは 6 ヶ月以上かけて削った結果で、ここから増やす場合は L-024〜L-026 (`rules/common/learned.md`) を先に読むことを推奨

## 8. 質問・改善案

[issue](../../issues) でお願いします。本 kit を題材にした記事 / フォーク歓迎です。
