#!/usr/bin/env bash
# 只读助手：M0 发布固定 SHA 之后，列出契约文档相对上一轮对齐基准的**增量**改动。
#
# 用法（在仓库根目录执行）：
#   bash docs/scheduler/tools/contract-diff-check.sh <新的固定SHA>
#
# 设计约束：
#   - 只读：不修改仓库任何文件，不联网，只使用本地已 fetch 的 git 对象。
#   - 用途单一：帮 B 在拿到新 SHA 后「只看增量」，不触发完整评审。
#   - 先执行 `git fetch upstream`，否则新 SHA 的文档对象可能不在本地。
#
# 维护人：B（M2）　基准：`upstream/feat/m0-api-contract` @ c9dda83
set -uo pipefail

BASE_SHA="c9dda83"
CONTRACT_FILE="docs/contracts/agent-api-v1.md"
EXAMPLES_FILE="docs/contracts/agent-api-v1.examples.json"
NEW_SHA="${1:-}"

if [[ -z "$NEW_SHA" ]]; then
  echo "用法: bash docs/scheduler/tools/contract-diff-check.sh <新的固定SHA>"
  echo "提示: 先 git fetch upstream，否则可能读不到该对象。"
  exit 2
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

OLD_FILE="$TMP_DIR/old.md"
NEW_FILE="$TMP_DIR/new.md"

if ! git cat-file -e "${BASE_SHA}:${CONTRACT_FILE}" 2>/dev/null; then
  echo "错误：本地找不到 ${BASE_SHA}:${CONTRACT_FILE}，请先执行 git fetch upstream。"
  exit 1
fi
if ! git cat-file -e "${NEW_SHA}:${CONTRACT_FILE}" 2>/dev/null; then
  echo "错误：本地找不到 ${NEW_SHA}:${CONTRACT_FILE}。"
  echo "可能原因：(1) 还没 git fetch upstream；(2) SHA 写错；(3) 契约文件路径有变。"
  exit 1
fi

git show "${BASE_SHA}:${CONTRACT_FILE}" > "$OLD_FILE"
git show "${NEW_SHA}:${CONTRACT_FILE}" > "$NEW_FILE"

echo "=============================================="
echo " 契约增量 diff：${BASE_SHA} → ${NEW_SHA}"
echo " 基准是有形式的上一轮对齐版本，不是猜测。"
echo "=============================================="

Added=$(diff <(cat "$OLD_FILE") <(cat "$NEW_FILE") | grep -c '^>')
Removed=$(diff <(cat "$OLD_FILE") <(cat "$NEW_FILE") | grep -c '^<')

echo
echo "[1] 变更规模：新增 ${Added} 行 / 删除 ${Removed} 行"
if [[ "$Added" -eq 0 && "$Removed" -eq 0 ]]; then
  echo "    → 契约文本与基准完全一致，无需增量对齐（但仍需向 M0 确认这就是最终稿）。"
fi

echo
echo "[2] 统一错误码表的变化（§4.1）"
CODES_OLD=$(grep -oP '^\| `\K[A-Z][A-Z_]+' "$OLD_FILE" | sort -u)
CODES_NEW=$(grep -oP '^\| `\K[A-Z][A-Z_]+' "$NEW_FILE" | sort -u)
diff <(echo "$CODES_OLD") <(echo "$CODES_NEW") | grep '^[<>]' | sed 's/^/    /' || true
if ! diff -q <(echo "$CODES_OLD") <(echo "$CODES_NEW") >/dev/null; then
  echo "    ↑ 上面是错误码集合的变化，逐个确认是否影响 C 的四项判定。"
else
  echo "    （无变化）"
fi

echo
echo "[3] 工具清单的变化（§6.x 小节）"
diff <(grep -E '^### 6\.[0-9]' "$OLD_FILE") <(grep -E '^### 6\.[0-9]' "$NEW_FILE") | grep '^[<>]' | sed 's/^/    /' || true
if diff -q <(grep -E '^### 6\.[0-9]' "$OLD_FILE") <(grep -E '^### 6\.[0-9]' "$NEW_FILE") >/dev/null; then
  echo "    （无变化，仍是七个工具）"
fi

echo
echo "[4] 冻结条款关键字的出现次数变化（有变化才列出）"
KEYWORDS=(
  'PROPOSAL_NOT_APPROVABLE'
  'READBACK_PENDING'
  'READBACK_MISMATCH'
  'ALREADY_APPLIED'
  'APPROVAL_CONSUMED'
  'token_issued'
  'related_task_ids'
  'WINDOW_INSUFFICIENT'
  'remaining_minutes_today'
  'input_digest'
)
for kw in "${KEYWORDS[@]}"; do
  before=$(grep -c -- "$kw" "$OLD_FILE" || true)
  after=$(grep -c -- "$kw" "$NEW_FILE" || true)
  if [[ "$before" != "$after" ]]; then
    echo "    ${kw}: ${before} → ${after}"
  fi
done

echo
echo "[5] Proposal / Token TTL 相关段落是否变化"
diff <(grep -n -E '30 分钟|5 分钟|TTL' "$OLD_FILE" | cut -d: -f2-) \
     <(grep -n -E '30 分钟|5 分钟|TTL' "$NEW_FILE" | cut -d: -f2-) \
  | grep '^[<>]' | sed 's/^/    /' || true

echo
echo "[6] M2 输出直接相关的章节：§5.6 / §5.7"
diff <(sed -n '/^### 5.6/,/^## 6\./p' "$OLD_FILE") \
     <(sed -n '/^### 5.6/,/^## 6\./p' "$NEW_FILE") \
  | grep '^[<>]' | sed 's/^/    /' || true

echo
echo "[7] 示例文件 ${EXAMPLES_FILE}"
if git cat-file -e "${BASE_SHA}:${EXAMPLES_FILE}" 2>/dev/null &&
  git cat-file -e "${NEW_SHA}:${EXAMPLES_FILE}" 2>/dev/null; then
  OLD_EX="$TMP_DIR/old.json"
  NEW_EX="$TMP_DIR/new.json"
  git show "${BASE_SHA}:${EXAMPLES_FILE}" > "$OLD_EX"
  git show "${NEW_SHA}:${EXAMPLES_FILE}" > "$NEW_EX"

  ExAdded=$(diff "$OLD_EX" "$NEW_EX" | grep -c '^>')
  ExRemoved=$(diff "$OLD_EX" "$NEW_EX" | grep -c '^<')
  echo "    变更规模：新增 ${ExAdded} 行 / 删除 ${ExRemoved} 行"

  echo
  echo "[8] 示例文件：tools 清单变化"
  diff <(grep -oP '"\K(list_tasks|get_calendar_events|generate_schedule|validate_schedule|request_approval|get_approval_status|apply_approved_changes)(?=")' "$OLD_EX" | sort -u) \
    <(grep -oP '"\K(list_tasks|get_calendar_events|generate_schedule|validate_schedule|request_approval|get_approval_status|apply_approved_changes)(?=")' "$NEW_EX" | sort -u) \
    | grep '^[<>]' | sed 's/^/    /' || true

  echo
  echo "[9] 示例文件：示例条目清单变化（新增/删除/改名都会列出来）"
  diff <(grep -oP '"name": "\K[a-z0-9_]+' "$OLD_EX") \
    <(grep -oP '"name": "\K[a-z0-9_]+' "$NEW_EX") \
    | grep '^[<>]' | sed 's/^/    /' || true

  echo
  echo "[10] 示例文件：M2 相关关键字计数变化（有变化才列出，含本轮新盯的字段）"
  EX_KEYWORDS=(
    'duration_target_seconds'
    'remaining_minutes_today'
    'scheduling_weight'
    'minimum_block_minutes'
    'duration_source'
    'task_target'
    'scheduler_estimate'
    'scheduled_at'
    'planned_date'
    'reason_code'
    'related_task_ids'
    'explanations'
    'unplanned_tasks'
    'applied_changes'
    'readback_verified'
    'input_digest'
  )
  for kw in "${EX_KEYWORDS[@]}"; do
    before=$(grep -c -- "$kw" "$OLD_EX" || true)
    after=$(grep -c -- "$kw" "$NEW_EX" || true)
    if [[ "$before" != "$after" ]]; then
      echo "    ${kw}: ${before} → ${after}"
    fi
  done
else
  echo "    跳过：新旧 SHA 中至少一方没有这份示例文件。"
  echo "    若 M0 后续增删契约文件清单，这里会提醒基准已失效而非静默通过。"
fi

echo
echo "=============================================="
echo " 下一步人工判断：对照 docs/scheduler/incremental-checklist-next-sha.md"
echo " 只看那里列出的条目，其余不重新评审。"
echo "=============================================="
