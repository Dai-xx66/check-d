# M1 证据补齐清单（C / M3 侧口径）

- **依据**：M0 2026-11-01T15:11Z 邮件 §二（"请 M1 与你对齐证据清单，补齐 X1-a、T3 原始响应；X1-2 单独提供可核验的 `writes_delta`；没有 raw 的项目继续标未测"）
- **对象**：`docs/contracts/reviews/m1-evidence-c9dda83.json`（PR #3 分支）
- **判定工具**：`tools/m3-checks/verify_m1_evidence.py`、`tools/m3-checks/assert_brail_contract.py`
- **原则**：清单只认**机器可读字段**，不认摘要、不认文字说明、不认 `pass: true`。字段缺失 → 该项记「未测」，不记 FAIL，但也不能升 E1。

---

## 1. 为什么要"清单"而不是"再补一遍"

上一轮（`1d4f3f2`）M1 补了字段，但补在了 `got` 字符串里，`raw` 是空的：

```json
{"case":"X1-a 首次写入 → READBACK_PENDING","got":"READBACK_PENDING","pass":true}   ← raw 缺失
```

我的脚本只能读 `raw`，读不到就判"不可判定"。这不是谁对谁错，是**双方对"记录"的定义不同**。所以本次把要什么写到字段级，一次对齐，避免第三轮返工。

## 2. 四个必填字段（每条 `READBACK_*` / 零写入类用例都要）

| 字段 | 类型 | 取值 | 判定用途 |
|---|---|---|---|
| `raw.proposal_status` | string | `applying` / `readback_pending` / `failed` | §4.1 强制；缺失即「未测」 |
| `raw.writes_delta` | **int** | 服务端写入计数器在**该次调用**前后的差值 | 零写入的唯一可核验形式；缺失即「未测」 |
| `raw.retryable` | bool | `true` / `false` | 与契约示例 #21/#31/#34 对齐 |
| `raw.details` | array | **响应原样**的 `details` 数组 | 字段名与条目完整性 |

`raw.writes_delta` 必须是**数字**，来自 mock 自己的计数器（如 `STATE`/flags 里的 `writes`），在调用前后各取一次相减；不接受"响应里说 0"或"文案写零写入"。

## 3. 逐条要什么

### 3.1 `X1-a 首次写入 → READBACK_PENDING`（当前无 raw）

```json
"raw": {
  "code": "READBACK_PENDING",
  "path": "new_key+readback_pending",
  "proposal_status": "readback_pending",
  "writes_delta": 0,
  "retryable": true,
  "details": [
    {"field": "proposal_status", "reason": "readback_pending"},
    {"field": "business_write_count_delta", "reason": "0"}
  ]
}
```

> 若该用例的 Proposal 真实状态是 `applying`（例如写后立刻查），`proposal_status` 就填 `applying`、`path` 填 `new_key+applying`。**填真实值，不要为了好看填另一个**——两条都合法，填错才 FAIL。

### 3.2 `T3 applying 同键 → IDEMPOTENCY_IN_PROGRESS`（当前无 raw）

先响应 `READBACK_PENDING`、同键重试后 → `IDEMPOTENCY_IN_PROGRESS`，是两步。请拆成两层记录：

```json
"raw": {
  "steps": [
    {"step": 1, "code": "READBACK_PENDING", "proposal_status": "applying",
     "writes_delta": 0, "retryable": true},
    {"step": 2, "code": "IDEMPOTENCY_IN_PROGRESS", "retryable": true,
     "writes_delta": 0}
  ],
  "proposal_status": "applying",
  "writes_delta": 0,
  "retryable": true
}
```

顶层的 `proposal_status` / `writes_delta` 填**整条用例全过程**的值（本次即 `applying` / `0`）。

### 3.3 `X1-2 同键重试 → 只回读且零写入`（有 details，缺独立计数）

保留现在的 `details`，另加服务端计数：

```json
"raw": {
  "code": "READBACK_PENDING",
  "path": "same_key+readback_pending",
  "proposal_status": "readback_pending",
  "writes_delta": 0,
  "retryable": true,
  "operation": "readback_only",
  "details": [ ... 原样 ... ]
}
```

`writes_delta: 0` 是这条的**唯一硬证据**——它证明"同键重试只回读、没有第二次 apply"。

### 3.4 崩溃后状态（新增，当前证据集完全没有）

现有 14 条 core 里**没有任何一条** `proposal_status = applying` 的原始记录，而崩溃路径正是唯一能观测它的地方。请补一条：

```json
"case": "X1-3 消费后崩溃 → READBACK_PENDING（applying）",
"expected": "READBACK_PENDING, proposal_status=applying, writes_delta=0",
"got": "READBACK_PENDING",
"pass": true,
"raw": {
  "code": "READBACK_PENDING",
  "path": "crash_after_consume",
  "proposal_status": "applying",
  "writes_delta": 0,
  "retryable": true,
  "details": [
    {"field": "proposal_status", "reason": "applying"},
    {"field": "business_write_count_delta", "reason": "0"}
  ]
}
```

## 4. 两条格式纪律（否则会被判「不可当单次判定」）

1. `got` 里不要写 `A -> B` 这种箭头。要表达两步，用 §3.2 的 `raw.steps` 结构；箭头会让判读为"修复前后"而无法当单次运行。`T2`（`PROPOSAL_INVALID -> APPROVAL_CONSUMED`）目前就是这个问题，建议一并用 `steps` 改掉。
2. **fixture 与示例不一致时，在 `note` 里写明差异并说明为何只能作信封级证据**（`EX-01` 4 任务 vs 示例 2 任务 已按此处理，无需再改）。

## 5. 提交前自检（你可以直接跑，通过再发我）

```bash
# 1) 证据字段自检：0 冲突、A 类 0 即合格（B 类只影响"零写入"结论）
python tools/m3-checks/verify_m1_evidence.py \
  --evidence <你的分支>:docs/contracts/reviews/m1-evidence-c9dda83.json \
  --contract c9dda83

# 2) 闸门自检：exit 0 即 Mock 行为合契约
python tools/m3-checks/assert_brail_contract.py <path>/tools/m1-mock/tool_server.py
```

> **口径已收紧（2026-11-02 22:10，据 M0 12:54Z 意见）**：核验器不再从 `expected/got/note` 文本回退提取 `proposal_status`，零写入也改为**按错误码类别**判定（不看文案里有没有"零写入"三个字）；`writes_delta` 必须是 int，字符串不接受。输出分成 **A 类（`READBACK_*` 缺必填 raw 字段，硬缺口）/ B 类（零写入类缺计数器）/ 冲突（exit 1）**。已用"删 raw 留文本"的反例回归验证，不再出现"补了仍判不了"或"没补却判齐"。

两条都过，我这边只需复跑同样两条命令即可确认，不需要你再准备别的东西。

> **本清单已自验**：按 §3 的四个 `raw` 结构造了一份样例（`X1-a` / `X1-2` / `X1-3` / `T3`），跑 `verify_m1_evidence.py` 得 **0 冲突 / 0 证据不足 / 0 需说明 / exit 0**。即：按上面写，就能被判为可引用，不会出现"补了仍判不了"。

## 6. 边界（不进本清单）

- 本清单不要求真实端点、可信身份、生产回读——那些仍是 A 轨前置，BLOCKED 不变。
- 补齐证据**不会**把 X1 / T03-b / Y1 升为 PASS：它们要的是完整链路 + 真实断言，Mock 证据最高只能到 E1。
- 本清单不改变 M0 的 4 项修复范围，也不新增功能要求。

---

编制：钟钰芬（C / M3）｜2026-11-02｜依据 M0 15:11Z 裁定 §二
