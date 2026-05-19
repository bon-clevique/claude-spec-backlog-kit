---
name: spec
description: Create a design Spec as a Markdown file at cwd's git toplevel `docs/specs/<title>.md` (Japanese title OK) AND upload it to the Notion DB "Claude Code Specs" as the persistent SoT. Use when user wants to capture design discussion (Context/Goal/Non-Goal/Acceptance/DA/Design/Risks) before moving into Plan Mode. Notion stores edits incrementally on the same page (no duplicates). Accepts optional argument: bare natural-language request, local .md file path, or Notion page URL.
metadata:
  author: bon
  version: "2.1.0"
  argument-hint: "[<自然言語要求> | <local .md path> | <Notion page URL>]"
---

# spec

## Mandatory First Action (Phase 0)

When this skill is invoked, c2 main session **must** Read the following file as its first tool call (before any other action):

- `~/.claude/rules/_lazy/delivery.md` — Delivery rules required for the Spec/Plan → PR → merge flow

This Read is **not a judgment call**: skill invocation = automatic system-reminder injection = physical enforcement. The instruction below is not optional, and c2 must not skip it because "the user's request seems light" — the Spec drafting in this skill always assumes delivery knowledge is hydrated.

会話文脈または引数で渡された source を起点に設計議論をまとめ、cwd の git toplevel `docs/specs/<日本語 title>.md` に **md ファイル** として永続化し、同時に Notion DB「Claude Code Specs」へ upload する skill。Notion 上の同 page を編集中の繰り返し上書きで更新し、user OK 後にローカル md を削除して Notion を SoT とする。

## Usage — 4 起動パターン

`/spec` は 0 個または 1 個の引数を取る。c2 は **第 1 トークンを以下の規則で classify** し、対応する Mode に分岐する。

| Mode | 引数の形 | c2 の動き |
|---|---|---|
| **M1: Context** | 引数なし | 起動以前の会話文脈を要約 → 必要なら質問 → Spec 作成 |
| **M2: NLR** (Natural Language Request) | 上記以外の自由文字列 (URL/path どちらでもない) | 引数を「ユーザー要求」として受領 → 不足情報を質問 → 揃ったら Spec 作成 |
| **M3: LocalMD** | 既存 local file path (`.md` 推奨、絶対/相対どちらも可) で `Read` 成功するもの | 該当ファイルを `Read` で取得 → 内容を起点に質問 → 揃ったら Spec 作成 |
| **M4: NotionURL** | `https://www.notion.so/...` または `https://<workspace>.notion.site/...` | `~/.claude/scripts/notion/read_page.py <url> --format markdown` で page 内容取得 → 起点に質問 → 揃ったら Spec 作成 |

### 引数 classification アルゴリズム (c2 が turn 内で判定)

第 1 引数を `$ARG` とすると:

1. `$ARG` が空 → **M1**
2. `$ARG` が `https://` で始まり host が `notion.so` / `*.notion.site` → **M4**
3. `$ARG` を path として `Read` を試行し成功 → **M3** (拡張子が `.md`/`.markdown` でない場合のみ confirm を 1 回投げる)
4. 上記いずれにも該当しない → **M2** (自然言語要求として扱う)

> 注: classification は c2 の判断で行い、外部スクリプト化しない (引数 1 件の前置判定で済むため、Layer 1 の hook 化は YAGNI。norm N-2 「existing-systems-first」遵守)。

### 質問の出し方 (M2 / M3 / M4 共通)

source から **不足している Spec section** を c2 が抽出し、**最大 3 問まとめて** AskUserQuestion に並べる。並べる優先順位:

1. **Context / Goal の解像度** (なぜ・どこを目指すか)
2. **Acceptance Scenarios の閾値** (どう pass を判定するか)
3. **Out of Scope の境界** (やらないこと)

source 内で既に十分明瞭な項目はスキップ。**全 section が source から確定できる場合は質問せず即 Spec 作成へ進む**。

### タイトルの決め方

- **c2 が source から命名**: M1 は会話文脈、M2/M3/M4 は source 内容を要約した user 視点のタイトル
- **日本語推奨**: 短いセンテンス (15-40 字)、内容が一目でわかる動詞 + 目的語形式
- **避けるべき**: 半角スラッシュ `/`、改行、先頭末尾の空白、`spec-` のような prefix (DB 内で冗長)
- **Notion DB「設計名」property = ファイル名 = state file 名** がすべて一致する設計 (state ファイルが title をキーにして lookup する)

### 関連 Plan との対応

- Spec タイトルと Plan slug は **独立** (harness が Plan 作成時に別 slug を提示するため)
- Plan ファイル冒頭に **対応 Spec の Notion URL** を貼る (例: `> 対応 Spec: https://www.notion.so/<page-id>`)

## 動作

### Phase 1 — Spec 作成 (skill 起動時)

1. cwd の git toplevel を `git rev-parse --show-toplevel` で取得 (非 git なら fallback で `~/.claude` を使用)
2. `<toplevel>/docs/specs/` を mkdir -p
3. `templates/spec-default.md` を `<toplevel>/docs/specs/<title>.md` にコピー
4. c2 が会話文脈から各 section を Edit で埋める (Context / Glossary / Goal / Big Picture / Non-Goal / Acceptance / DA / Design / Risks / OoS)
5. `scripts/spec-create.sh "<title>"` が md を Notion DB「Claude Code Specs」へ upload し、page_id を `~/.claude/state/spec-page-<title>` に保存
6. **c2 は user に Notion URL を提示し、conversational 承認を求める** (Stop Whitelist (1) external blocker 該当、confirmation-leak ではない)

> 注: 実運用では skill 起動時に上記 1〜5 を一度に実行 (template コピー → c2 が section 埋め → spec-create.sh で upload) する。`spec-create.sh` は 1, 2, 3, 5 を担当し、4 (section 充填) は c2 main session が Edit tool で行う。具体的には: spec-create.sh をまず **template コピーのみ** で呼ぶ → c2 が Edit → 再度 spec-create.sh は呼ばず `spec-update.sh` で Notion 反映、というフロー。

### Phase 2 — Spec 編集 (user OK 前)

user から修正指示があれば:

1. c2 が `<toplevel>/docs/specs/<title>.md` を Edit で修正
2. `scripts/spec-update.sh "<title>"` が同 Notion page (state file の page_id) を上書き
3. c2 が user に「更新しました」を伝え再確認を依頼

### Phase 3 — 承認後 cleanup

user が OK を返したら:

1. `scripts/spec-finalize.sh "<title>"` がローカル md + state file を削除
2. Notion page (SoT) は残置
3. Plan Mode (`EnterPlanMode`) へ進み、対応 Plan を作成

## c2 の実運用手順 (新規 Spec を作るとき)

ユーザーが `/spec [<arg>]` を打ったら、c2 は以下を順に実行する:

```bash
# Step 0: 引数 classification (Mode 判定)
#   - 引数なし → M1 (会話文脈)
#   - https://(*.notion.so|*.notion.site)/... → M4 (Notion URL)
#   - Read 成功する path → M3 (local md file)
#   - 上記以外 → M2 (自然言語要求)

# Step 0.5: source 取得 (Mode 別)
#   M1: 会話文脈をそのまま使用 (追加取得なし)
#   M2: 引数文字列を要求として保持
#   M3: Read tool で内容取得
#   M4: 以下で markdown 化して取得
#       python3 ~/.claude/scripts/notion/read_page.py "<URL>" --format markdown

# Step 0.6: 不足情報の確認 (M2/M3/M4 で source から Spec 全 section が確定しない場合のみ)
#   - 最大 3 問を AskUserQuestion で 1 turn にまとめて投げる
#   - 全 section 確定なら質問せず Step 1 へ直行

# Step 1: source + 質問回答から日本語 title を決める (c2 の判断)
TITLE="<日本語タイトル>"

# Step 2: template から md を生成 (まだ TODO だらけ。upload はしない)
bash ~/.claude/skills/spec/scripts/spec-create.sh "$TITLE" --skip-upload

# Step 3: c2 が <toplevel>/docs/specs/<TITLE>.md を Edit tool で section ごとに埋める
#         (template 内の "TODO" を source + 質問回答から得た内容に置換)

# Step 4: 充填済 md を Notion へ初回 upload + state file に page_id 保存
bash ~/.claude/skills/spec/scripts/spec-create.sh "$TITLE"

# Step 5: user に Notion URL を提示し OK or 修正を待つ
#         修正があれば: Step 6 → Step 5 を反復
#         OK が返ったら: Step 7 へ

# Step 6: user 修正反映 (md を Edit → 同 Notion page を上書き)
bash ~/.claude/skills/spec/scripts/spec-update.sh "$TITLE"

# Step 7: cleanup (Notion を SoT として残す)
bash ~/.claude/skills/spec/scripts/spec-finalize.sh "$TITLE"

# Step 8: EnterPlanMode で対応 Plan 作成へ
```

### Mode 別の Step 0.5 詳細

- **M3 (LocalMD)**: 拡張子が `.md`/`.markdown` 以外でも Read 成功すればそのまま使う。binary ファイルや巨大ファイル (>2000 行) は Read offset/limit で section ごとに読み、要約してから Spec section に流し込む
- **M4 (NotionURL)**: `read_page.py` は `--format markdown` 出力で properties + content を一括取得する。取得失敗 (404 / auth / network) 時は user に URL 再確認を 1 度だけ求める (Stop Whitelist (1) external blocker)
- **M2 (NLR)**: 引数自体は典型的に 1〜3 行と短いので、Spec 全 section を埋めるには Step 0.6 で 1〜3 問の補足が必要なケースが多い。逆に引数が十分長文 (例: 仕様書 paste) なら無質問で進める

### spec-create.sh の二段呼び出し設計

- **1 回目** (`--skip-upload`): template を md ファイルとしてコピーするだけ。state file は作らない
- **2 回目** (flag なし): 既存 md (section 充填済) を Notion へ初回 upload、page_id を state file に保存

これにより c2 は「template → 充填 → upload」を素直な順序で書ける。同一 title で 3 回目以降の呼び出しは「state file が既に存在」エラーを返し、`spec-update.sh` への誘導を促す。

## 構造

生成される md は以下の 10 section を持つ:

- **§1 Context** — 問題・背景
- **§2 Glossary** — 主要用語の定義 (5 件固定)
- **§3 Goal** — 達成すべき最終状態
- **§4 Big Picture** — Goal 達成後の全体像 (User action 単位の sub-diagram で sequenceDiagram、必須)
- **§5 Non-Goal** — 明示的に対象外とすること
- **§6 Acceptance Scenarios** — Gherkin 形式の検証可能条件、Scenario ごとに code block 分割
- **§7 Devil's Advocate** — 6 sub-question (5 standard + 1 zero-base 削除候補) を箇条書きで構造化
- **§8 Design** — Phase ごとに sequenceDiagram sub-diagram (flowchart 不可)
- **§9 Risks & Mitigations** — HIGH/MED/LOW + 発生条件/対策/検証/ロールバック
- **§10 Out of Scope** — Backlog Discipline (a)+(b) 両満たす項目のみ

## Spec/Plan/Goal 連動

- `/spec` 後に Plan Mode で Plan 作成
- Plan は Spec を参照する形 (Plan file 冒頭に Notion URL)
- 必要なら Plan 承認後 `/goal "<Notion URL> の §Acceptance Scenarios 全 pass、各 scenario は spec を re-read して進捗を会話に出す"` で session-scoped 自走

## cwd が non-git の場合

`spec-create.sh` は cwd の git toplevel 検出に失敗したら、`~/.claude` を fallback toplevel として使用する (`~/.claude/docs/specs/<title>.md` に md を作成)。これにより user が `~/dev/` (非 git) 等から `/spec` を起動しても動作する。

## Notion DB

- DB: 「Claude Code Specs」
- `data_source_id`: `<UUID>` (`md_to_notion.py` の default、env `NOTION_SPEC_DATA_SOURCE_ID` で上書き可)
- Properties:
  - **設計名** (title) ← c2 命名タイトル
  - **Repo/Project** (rich_text) ← git toplevel basename
  - **ステータス** (status) ← `Plan` 固定 (新規作成時)
  - 概要 / タグ / 実装日 ← 空欄 (user が Notion 上で必要なら手動補完)
- 参照: `~/.claude/reference/notion-databases.md`

## 実装ファイル

- `scripts/spec-create.sh` — md 新規生成 + Notion 初回 upload + state file 作成
- `scripts/spec-update.sh` — md 編集を Notion 同 page へ反映
- `scripts/spec-finalize.sh` — user OK 後のローカル cleanup (Notion 残置)
- `scripts/md_to_notion.py` — md → Notion blocks 変換 + create/update API
- `templates/spec-default.md` — section テンプレ
