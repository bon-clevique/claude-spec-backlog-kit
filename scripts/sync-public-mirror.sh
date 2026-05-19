#!/usr/bin/env bash
set -euo pipefail

# claude-config 配下の Spec/Backlog 関連ファイルを公開 mirror repo に sanitize 済で export する
#
# Modes:
#   --init        Mirror repo を新規作成 (mkdir + git init + 全 whitelist ファイルコピー)
#   --verify      Mirror 配下の sanitize 漏れを検出 (exit 1 if any leak)
#   --dry-run     書き込み無しで予定動作を出力 (--init と組み合わせ可)
#   (no args)     既存 mirror に差分のみ同期
#
# Env:
#   KIT_TARGET    Mirror repo の path (default: $HOME/dev/<your-org>/claude-spec-backlog-kit)

# 自身の path
SOURCE_ROOT="$HOME/.claude"
TARGET_ROOT="${KIT_TARGET:-$HOME/dev/<your-org>/claude-spec-backlog-kit}"

# redact lib を source
source "$SOURCE_ROOT/scripts/lib/redact.sh"

# 同梱対象ファイル一覧 (本体 path / 相対 path、source root からの)
WHITELIST=(
  # skills/spec
  "skills/spec/SKILL.md"
  "skills/spec/scripts/spec-create.sh"
  "skills/spec/scripts/spec-update.sh"
  "skills/spec/scripts/spec-update-pr.sh"
  "skills/spec/scripts/spec-update-recap.sh"
  "skills/spec/scripts/spec-finalize.sh"
  "skills/spec/scripts/md_to_notion.py"
  "skills/spec/templates/spec-default.md"
  "skills/spec/templates/spec-default.README.md"

  # skills/backlog
  "skills/backlog/SKILL.md"
  "skills/backlog/implementation.md"
  "skills/backlog/scripts/add-internal.sh"
  "skills/backlog/scripts/atomic-write.sh"
  "skills/backlog/scripts/frontmatter-get.sh"
  "skills/backlog/scripts/frontmatter-set.sh"
  "skills/backlog/scripts/id-resolve.sh"
  "skills/backlog/scripts/scan.sh"
  "skills/backlog/scripts/slugify.sh"

  # scripts/hooks
  "scripts/hooks/plan-archive-on-merge.sh"
  "scripts/hooks/plan-current-recorder.js"
  "scripts/hooks/plan-enforce.js"
  "scripts/hooks/plan-approval-marker.js"
  "scripts/hooks/completion-gate.js"
  "scripts/hooks/confirmation-leak-detector.js"

  # scripts/notion
  "scripts/notion/read_page.py"
  "scripts/notion/create_db.py"
  "scripts/notion/edit_db.py"
  "scripts/notion/notion_wrapper.py"

  # scripts/lib
  "scripts/lib/plan-pr-target-resolver.sh"
  "scripts/lib/branch-from-plan.sh"
  "scripts/lib/project-slug.sh"
  "scripts/lib/mini-da-template.sh"
  "scripts/lib/redact.sh"

  # scripts root
  "scripts/create-draft-pr.sh"
  "scripts/sync-public-mirror.sh"

  # templates
  "templates/plan-default.md"
  "templates/pull-request-template.md"
  "templates/delivery-manager-prompt.md"
  "templates/action-default.md"
  "templates/settings.jsts.json"
  "templates/nested-team-director-prompt.md"
  "templates/nested-team-issue.md"
  "templates/nested-team-manager-prompt.md"
  "templates/nested-team-master-plan.md"
  "templates/nested-team-phase-plan.md"

  # rules
  "rules/common/workflow-enforcement.md"
  "rules/common/coding-standards.md"

  # root
  "BACKLOG.md"
  "CLAUDE.md"

  # reference
  "reference/notion-databases.md"

  # agents
  "agents/security-reviewer.md"
  "agents/code-reviewer.md"
  "agents/architect.md"
  "agents/pdm-reviewer.md"
  "agents/ceo-reviewer.md"
  "agents/ops-reviewer.md"
  "agents/dx-reviewer.md"
  "agents/planner.md"
  "agents/mini-da.md"
  "agents/backlog-task-manager.md"

  # settings
  "settings.json"
)

mode_init() {
  # 1. 前提チェック: TARGET_ROOT が既存 & 非空なら abort
  if [ -d "$TARGET_ROOT" ] && [ -n "$(ls -A "$TARGET_ROOT" 2>/dev/null)" ]; then
    echo "Error: TARGET_ROOT already exists and is not empty. Use sync mode instead." >&2
    exit 2
  fi

  # 2. ディレクトリ作成
  mkdir -p "$TARGET_ROOT"

  # 3. git init (-b main 指定で main branch を初期化)
  git -C "$TARGET_ROOT" init -b main >/dev/null

  # 4. whitelist 反復: redact しつつコピー、件数をカウント
  local copied=0
  local skipped=0
  local rel_path src dest dest_dir
  for rel_path in "${WHITELIST[@]}"; do
    src="$SOURCE_ROOT/$rel_path"
    dest="$TARGET_ROOT/$rel_path"

    if [ ! -e "$src" ]; then
      echo "Warning: source not found: $rel_path, skip" >&2
      skipped=$((skipped + 1))
      continue
    fi

    dest_dir="$(dirname "$dest")"
    mkdir -p "$dest_dir"

    # sanitize 済コピー (stdin → redact_content → stdout)
    redact_content < "$src" > "$dest"

    # 元ファイルが実行可能なら DEST も chmod 755
    if [ -x "$src" ]; then
      chmod 755 "$dest"
    fi

    copied=$((copied + 1))
  done

  # 5. mirror 専用ファイル生成
  cat > "$TARGET_ROOT/README.md" <<'EOF'
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

- AI に実装を任せたら、自分の仕事は『何を作るか』と『やらないこと』だけになった (前編) — 現状の Spec + Backlog 運用
- ルール1247行→2行にした話。AIに本当に任せるための規律設計術 (後編) — そこに至るまでの 1 週間の悪戦苦闘

(blog 公開時に zenn URL を追記)

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
EOF

  cat > "$TARGET_ROOT/LICENSE" <<'EOF'
MIT License

Copyright (c) 2026 <your-github-user>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF

  cat > "$TARGET_ROOT/.gitignore" <<'EOF'
# 二重ガード: 万一の混入を catch するための ignore
.DS_Store
*.swp
*.log
state/
actions/
backlog/
__pycache__/
*.pyc
.env
.env.*
EOF

  # 6. verify_clean 最終確認
  if ! verify_clean "$TARGET_ROOT"; then
    echo "Error: sanitize leak detected. Rolling back $TARGET_ROOT" >&2
    rm -rf "$TARGET_ROOT"
    echo "Error: --init aborted (verify_clean failed)" >&2
    exit 1
  fi

  # 7. 完了報告
  cat <<EOF
✓ --init complete
  TARGET_ROOT: $TARGET_ROOT
  copied: $copied files (skipped: $skipped)
  verify: PASS
Next:
  cd $TARGET_ROOT
  git add -A && git commit -m "init: claude-spec-backlog-kit"
  # Phase A: gh repo create --private (Plan Step 7)
EOF
}

mode_sync() {
  # 1. 前提チェック: TARGET_ROOT が既存 & .git/ ありを確認
  if [ ! -d "$TARGET_ROOT" ] || [ ! -d "$TARGET_ROOT/.git" ]; then
    echo "Error: TARGET_ROOT not initialized. Run with --init first." >&2
    exit 2
  fi

  # 2. tmp file 用 trap (set -u 下では関数 scope の local が EXIT 時には消えるため default 展開を使う)
  local tmp=""
  trap 'rm -f "${tmp:-}"' EXIT

  # 3. whitelist 反復: redact → cmp 比較 → 差分のみ上書き
  local changed=0
  local unchanged=0
  local skipped=0
  local rel_path src dest dest_dir
  for rel_path in "${WHITELIST[@]}"; do
    src="$SOURCE_ROOT/$rel_path"
    dest="$TARGET_ROOT/$rel_path"

    if [ ! -e "$src" ]; then
      echo "Warning: source not found: $rel_path, skip" >&2
      skipped=$((skipped + 1))
      continue
    fi

    # tmp file 生成 (mktemp は BSD/GNU 双方対応の base form を使う)
    tmp="$(mktemp)"

    # sanitize 済 content を tmp に書き出す
    redact_content < "$src" > "$tmp"

    if [ ! -e "$dest" ]; then
      # DEST 不在: 新規コピー
      dest_dir="$(dirname "$dest")"
      mkdir -p "$dest_dir"
      mv "$tmp" "$dest"
      tmp=""
      if [ -x "$src" ]; then
        chmod 755 "$dest"
      fi
      changed=$((changed + 1))
    elif cmp -s "$tmp" "$dest"; then
      # 一致: skip (tmp は次 iteration の冒頭 mktemp で上書きされるが、明示的に削除)
      rm -f "$tmp"
      tmp=""
      unchanged=$((unchanged + 1))
    else
      # 不一致: 上書き
      mv "$tmp" "$dest"
      tmp=""
      if [ -x "$src" ]; then
        chmod 755 "$dest"
      fi
      changed=$((changed + 1))
    fi
  done

  # 4. verify_clean 最終確認 (rollback はしない、既存 mirror を残す)
  if ! verify_clean "$TARGET_ROOT"; then
    echo "Error: sanitize leak detected after sync. Mirror left intact for inspection." >&2
    exit 1
  fi

  # 5. git status 表示
  local git_status_output
  git_status_output="$(cd "$TARGET_ROOT" && git status --short)"

  # 6. 完了報告
  cat <<EOF
✓ sync complete
  TARGET_ROOT: $TARGET_ROOT
  changed: $changed files (unchanged: $unchanged, skipped: $skipped)
  verify: PASS
Git status:
$git_status_output
Next:
  cd $TARGET_ROOT
  git diff   # 差分レビュー
  git add -A && git commit -m "sync: <message>"
  git push   # mirror repo へ
EOF
}

mode_verify() {
  # 1. 前提チェック: TARGET_ROOT が存在しない場合は abort
  if [[ ! -d "$TARGET_ROOT" ]]; then
    echo "Error: TARGET_ROOT does not exist: $TARGET_ROOT" >&2
    exit 2
  fi

  # 2. tmp file 用 trap (関数 scope、RETURN 時に削除)
  local tmp_stderr
  tmp_stderr=$(mktemp)
  # shellcheck disable=SC2064
  trap "rm -f '$tmp_stderr'" RETURN

  # 3. verify_clean を呼び、stderr を tmp に retain (set -e 下でも non-zero を捕捉)
  local rc=0
  verify_clean "$TARGET_ROOT" 2>"$tmp_stderr" || rc=$?

  # 4. verify_clean の元の output を素通し
  cat "$tmp_stderr" >&2

  # 5. summary 表示
  if [[ $rc -eq 0 ]]; then
    echo "✓ verify clean: $TARGET_ROOT"
    return 0
  else
    local count
    count=$(wc -l < "$tmp_stderr" | tr -d ' ')
    echo "✗ verify FAILED: $count leak(s) found in $TARGET_ROOT" >&2
    return 1
  fi
}

mode_dry_run() {
  local target_mode="${1:-sync}"

  # 1. WHITELIST Read 確認 + redact 適用件数の計測 (実書き込み無し)
  local ok_count=0
  local miss_count=0
  local changed_by_redact=0
  local rel_path src tmp_src tmp_redacted
  for rel_path in "${WHITELIST[@]}"; do
    src="$SOURCE_ROOT/$rel_path"
    if [ ! -e "$src" ]; then
      echo "[MISS]  $rel_path" >&2
      miss_count=$((miss_count + 1))
      continue
    fi
    echo "[OK]    $rel_path"
    ok_count=$((ok_count + 1))

    # redact 前後の差分を cmp で判定 (実書き込みなし、tmp は即破棄)
    tmp_redacted="$(mktemp)"
    redact_content < "$src" > "$tmp_redacted"
    if ! cmp -s "$src" "$tmp_redacted"; then
      changed_by_redact=$((changed_by_redact + 1))
    fi
    rm -f "$tmp_redacted"
  done

  # 2. mode 別の差分予測
  local total=${#WHITELIST[@]}
  case "$target_mode" in
    init)
      if [ -d "$TARGET_ROOT" ] && [ -n "$(ls -A "$TARGET_ROOT" 2>/dev/null)" ]; then
        cat <<EOF
[DRY-RUN --init]
  Source: $SOURCE_ROOT
  Target: $TARGET_ROOT (already EXISTS and non-empty)
  Whitelist: $total entries
    OK: $ok_count
    MISS: $miss_count
  Would abort: TARGET_ROOT already exists
No changes made (dry-run).
EOF
      else
        cat <<EOF
[DRY-RUN --init]
  Source: $SOURCE_ROOT
  Target: $TARGET_ROOT (would be CREATED)
  Whitelist: $total entries
    OK: $ok_count
    MISS: $miss_count
  Sanitize: $changed_by_redact files would be modified by redact
  Mirror-only files: README.md, LICENSE, .gitignore would be generated
  Verify: would be invoked at end (rollback if any leak)
No changes made (dry-run).
EOF
      fi
      ;;
    verify)
      cat <<EOF
[DRY-RUN --verify]
  Target: $TARGET_ROOT
  Would invoke: verify_clean $TARGET_ROOT
No changes made (dry-run).
EOF
      ;;
    sync|*)
      if [ ! -d "$TARGET_ROOT" ] || [ ! -d "$TARGET_ROOT/.git" ]; then
        cat <<EOF
[DRY-RUN sync]
  Source: $SOURCE_ROOT
  Target: $TARGET_ROOT (not initialized)
  Whitelist: $total entries
    OK: $ok_count
    MISS: $miss_count
  Would abort: TARGET_ROOT not initialized
No changes made (dry-run).
EOF
      else
        # TARGET 存在 + .git/ あり: 各 SRC を redact した結果と既存 DEST を比較
        local predicted_changed=0
        local predicted_unchanged=0
        local predicted_new=0
        local dest tmp_redacted2
        for rel_path in "${WHITELIST[@]}"; do
          src="$SOURCE_ROOT/$rel_path"
          dest="$TARGET_ROOT/$rel_path"
          [ ! -e "$src" ] && continue
          if [ ! -e "$dest" ]; then
            predicted_new=$((predicted_new + 1))
            continue
          fi
          tmp_redacted2="$(mktemp)"
          redact_content < "$src" > "$tmp_redacted2"
          if cmp -s "$tmp_redacted2" "$dest"; then
            predicted_unchanged=$((predicted_unchanged + 1))
          else
            predicted_changed=$((predicted_changed + 1))
          fi
          rm -f "$tmp_redacted2"
        done
        cat <<EOF
[DRY-RUN sync]
  Source: $SOURCE_ROOT
  Target: $TARGET_ROOT (initialized)
  Whitelist: $total entries
    OK: $ok_count
    MISS: $miss_count
  Predicted: changed=$predicted_changed, unchanged=$predicted_unchanged, new=$predicted_new
  Verify: would be invoked at end
No changes made (dry-run).
EOF
      fi
      ;;
  esac
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [--init|--verify|--dry-run]

  --init        新規 mirror repo を作成
  --verify      sanitize 漏れを検出
  --dry-run     実書き込み無しで予定動作を出力 (--init と組合せ可)
  (no args)     既存 mirror に差分のみ同期

Env:
  KIT_TARGET=<path>   Mirror repo path を上書き (default: \$HOME/dev/<your-org>/claude-spec-backlog-kit)
EOF
}

main() {
  local mode="sync"  # default
  local dry_run=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --init)    mode="init"; shift ;;
      --verify)  mode="verify"; shift ;;
      --dry-run) dry_run=1; shift ;;
      --help|-h) usage; exit 0 ;;
      *)         echo "Unknown arg: $1" >&2; usage; exit 1 ;;
    esac
  done

  if [[ $dry_run -eq 1 ]]; then
    mode_dry_run "$mode"
  else
    case "$mode" in
      init)   mode_init ;;
      verify) mode_verify ;;
      sync)   mode_sync ;;
    esac
  fi
}

main "$@"
