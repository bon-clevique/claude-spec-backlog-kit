#!/usr/bin/env bash
# redact.sh — sanitize lib for claude-spec-backlog-kit public mirror sync
#
# これは lib script です。単独実行用ではなく、以下のように source して使います:
#   source ~/.claude/scripts/lib/redact.sh
#   echo "$content" | redact_content > "$out"
#   verify_clean "$mirror_dir"
#
# 提供関数:
#   redact_content   — stdin の text を sanitize して stdout に出力
#   verify_clean DIR — DIR 配下に sanitize 漏れが無いか grep で検査 (.git/ 除外)
#
# Self-test:
#   bash ~/.claude/scripts/lib/redact.sh --self-test
#
# 設計参照: Plan eventual-foraging-clarke.md §Sanitize ルール
# Sed expression は precedence 高 → 低 で (1)credential → (2)識別子 → (3)個人/事業 → (4)Notion URL
# BSD sed / GNU sed 両対応のため `sed -E` + POSIX class ([0-9] / [[:space:]]) のみ使用

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# redact_content: stdin → sanitize → stdout
# ─────────────────────────────────────────────────────────────────────────────
redact_content() {
  sed -E \
    -e 's/NOTION_API_KEY=secret_[A-Za-z0-9]+/NOTION_API_KEY=<your-notion-api-key>/g' \
    -e 's/secret_[A-Za-z0-9]{40,}/<REDACTED-NOTION-KEY>/g' \
    -e 's/ghp_[A-Za-z0-9]{36,}/<REDACTED-GH-PAT>/g' \
    -e 's/gho_[A-Za-z0-9]{36,}/<REDACTED-GH-OAUTH>/g' \
    -e 's/ghu_[A-Za-z0-9]{36,}/<REDACTED-GH-USER>/g' \
    -e 's/ghs_[A-Za-z0-9]{36,}/<REDACTED-GH-SERVER>/g' \
    -e 's/ghr_[A-Za-z0-9]{36,}/<REDACTED-GH-REFRESH>/g' \
    -e 's/sk-ant-[A-Za-z0-9_-]+/<REDACTED-ANTHROPIC-KEY>/g' \
    -e 's/AKIA[0-9A-Z]{16}/<REDACTED-AWS-AKID>/g' \
    -e 's/xox[bpars]-[0-9A-Za-z-]+/<REDACTED-SLACK-TOKEN>/g' \
    -e 's/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/<REDACTED-JWT>/g' \
    -e 's/sk_(live|test)_[A-Za-z0-9]{24,}/<REDACTED-STRIPE-SK>/g' \
    -e 's/pk_(live|test)_[A-Za-z0-9]{24,}/<REDACTED-STRIPE-PK>/g' \
    -e 's/-----BEGIN [A-Z ]+PRIVATE KEY-----[^-]*-----END [A-Z ]+PRIVATE KEY-----/<REDACTED-PRIVATE-KEY>/g' \
    -e 's/data_source_id("|'\'')?[[:space:]]*[:=][[:space:]]*("|'\'')?[a-f0-9-]{36}/data_source_id: <YOUR_DATA_SOURCE_ID>/g' \
    -e 's/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/<UUID>/g' \
    -e 's/<your-github-user>/<your-github-user>/g' \
    -e 's/[Cc]levique/<your-org>/g' \
    -e 's/[Tt]oukan/<your-app>/g' \
    -e 's/badfatcat\.biz/<your-email>/g' \
    -e 's/<user>@/<user>@/g' \
    -e 's#$HOME/#$HOME/#g' \
    -e 's#notion\.so/[a-z0-9-]+-[a-f0-9]{32}#notion.so/<YOUR-PAGE>#g'
  # Order note: <your-github-user> MUST come before [Cc]levique
  # (otherwise '<your-github-user>' would be partially matched by '<your-org>' → <your-org>)
}

# ─────────────────────────────────────────────────────────────────────────────
# verify_clean DIR: DIR 配下に sanitize 漏れがあれば file:line:pattern を stderr 出力、exit 1
# ─────────────────────────────────────────────────────────────────────────────
verify_clean() {
  local target_dir="${1:?usage: verify_clean <dir>}"
  if [ ! -d "$target_dir" ]; then
    echo "verify_clean: directory not found: $target_dir" >&2
    return 1
  fi

  local found=0
  local label pattern

  for entry in \
    "UUID|[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}" \
    "NOTION-KEY|secret_[A-Za-z0-9]{40,}" \
    "NOTION-API-ASSIGN|NOTION_API_KEY=secret_[A-Za-z0-9]+" \
    "PERSONAL|<your-github-user>|<your-app>|badfatcat|<your-org>" \
    "HOME-PATH|$HOME/" \
    "GH-OAUTH|gh[oush]_[A-Za-z0-9]{36,}" \
    "AWS-AKID|AKIA[0-9A-Z]{16}" \
    "SLACK-TOKEN|xox[bpars]-[0-9A-Za-z-]+" \
    "JWT|eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+" \
    "STRIPE-KEY|(sk|pk)_(live|test)_[A-Za-z0-9]{24,}" \
    "PRIVATE-KEY|-----BEGIN [A-Z ]+PRIVATE KEY-----"
  do
    label="${entry%%|*}"
    pattern="${entry#*|}"
    # PERSONAL は case-insensitive、その他は case-sensitive
    # redact.sh 自身は meta-text として patterns を保持するため self-exclude
    # (redact 規則そのものを記述するため、結果的に PERSONAL grep が hit する)
    local grep_opts=("-rEn" "--exclude-dir=.git" "--exclude=redact.sh")
    if [ "$label" = "PERSONAL" ]; then
      grep_opts+=("-i")
    fi
    # grep が見つけたら結果を整形して stderr に出す。grep 不検出は失敗扱いしない
    # pattern が `-----BEGIN ...` のように `-` で始まることがあるため `-e` で渡す
    local hits
    if hits=$(grep "${grep_opts[@]}" -e "$pattern" "$target_dir" 2>/dev/null); then
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        # line format: <file>:<lineno>:<content>
        local file_part="${line%%:*}"
        local rest="${line#*:}"
        local lineno_part="${rest%%:*}"
        echo "${file_part}:${lineno_part}: ${label}" >&2
        found=1
      done <<< "$hits"
    fi
  done

  if [ "$found" -eq 1 ]; then
    return 1
  fi
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Self-test: bash redact.sh --self-test
# ─────────────────────────────────────────────────────────────────────────────
_self_test() {
  local pass=0
  local total=7

  local -a inputs expected labels
  inputs=()
  expected=()
  labels=()

  # case 1: NOTION_API_KEY assignment
  inputs+=("NOTION_API_KEY=<your-notion-api-key>")
  expected+=("NOTION_API_KEY=<your-notion-api-key>")
  labels+=("case 1 (NOTION_API_KEY)")

  # case 2: data_source_id with UUID
  inputs+=("data_source_id: <YOUR_DATA_SOURCE_ID>")
  expected+=("data_source_id: <YOUR_DATA_SOURCE_ID>")
  labels+=("case 2 (data_source_id UUID)")

  # case 3: <your-github-user> + $HOME/ → 順序保証で <your-github-user> 内の <your-org> が二重置換されないこと
  inputs+=("<your-github-user>/claude-config $HOME/dev/<your-org>/")
  expected+=("<your-github-user>/claude-config \$HOME/dev/<your-org>/")
  labels+=("case 3 (<your-github-user> + HOME path, order safety)")

  # case 4: <your-app> + Notion URL with 32-hex page_id
  inputs+=("<your-app> https://www.notion.so/<YOUR-PAGE>")
  expected+=("<your-app> https://www.notion.so/<YOUR-PAGE>")
  labels+=("case 4 (<your-app> + Notion URL)")

  # case 5: GH OAuth token
  inputs+=("token: <REDACTED-GH-OAUTH>")
  expected+=("token: <REDACTED-GH-OAUTH>")
  labels+=("case 5 (GH OAuth)")

  # case 6: AWS Access Key + Slack token
  inputs+=("aws=<REDACTED-AWS-AKID> slack=<REDACTED-SLACK-TOKEN>")
  expected+=("aws=<REDACTED-AWS-AKID> slack=<REDACTED-SLACK-TOKEN>")
  labels+=("case 6 (AWS + Slack)")

  # case 7: JWT (3 dot-separated base64url segments starting with eyJ)
  inputs+=("Authorization: Bearer <REDACTED-JWT>")
  expected+=("Authorization: Bearer <REDACTED-JWT>")
  labels+=("case 7 (JWT)")

  local i
  for ((i = 0; i < total; i++)); do
    local got
    got=$(printf '%s' "${inputs[$i]}" | redact_content)
    if [ "$got" = "${expected[$i]}" ]; then
      echo "PASS: ${labels[$i]}"
      pass=$((pass + 1))
    else
      echo "FAIL: ${labels[$i]} (expected: ${expected[$i]}, got: $got)"
    fi
  done

  echo "${pass}/${total} PASS"
  if [ "$pass" -eq "$total" ]; then
    return 0
  fi
  return 1
}

_usage() {
  cat >&2 <<EOF
redact.sh — sanitize lib (source 用、単独実行用ではない)

Usage:
  source ~/.claude/scripts/lib/redact.sh
  echo "\$content" | redact_content
  verify_clean <dir>

Standalone:
  bash redact.sh --self-test   # 7 cases の self-test を実行
  bash redact.sh --help        # この usage を表示
EOF
}

# main: --self-test / --help / それ以外は usage を出して exit 1
# source 経由の場合 (BASH_SOURCE[0] != $0) は何もしない
if [ "${BASH_SOURCE[0]:-}" = "${0}" ]; then
  case "${1:-}" in
    --self-test) _self_test ;;
    --help|-h)   _usage ;;
    *)           _usage; exit 1 ;;
  esac
fi
