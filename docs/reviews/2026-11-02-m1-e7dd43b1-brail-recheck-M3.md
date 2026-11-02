# M3 复测：M1 `e7dd43b1d` B 轨契约闸门（G0–G6）+ 证据字段核验

- **复测人**：M3（钟钰芬）
- **时间**：2026-11-02 21:55（本地）/ 13:55Z
- **被测对象**：`Tony2215/check-d` @ `e7dd43b1dc28b0fb239a78c8335d761df15449db`（PR #3 head，分支 `review/m1-contract-v1`），文件 `tools/m1-mock/tool_server.py`（1111 行）
- **基准契约**：`c9dda83195a9af4b9ca762d8556fdd0e8d43010a`（B20 修复后的统一基准）
- **复测性质**：M0 甲方案的验收条件（"C 用同一探测脚本复测，全部通过后才一次性录完整 8 镜"）；同时回应 M0 2026-11-02T12:54Z 邮件对**核验器口径**的质疑
- **前次基线**：`1d4f3f2` → 3/7 不通过（`docs/reviews/2026-11-01-m1-mock-brail-probe-M3.md` §8）

## 1. 结论（一句话）

**闸门 7/7 全部通过（exit 0）；证据 `READBACK_*` 六条四个字段全齐（A 类缺口 0）→ 镜头 6 解封，B 轨 8 镜可一次性开录。** 另有 5 条"零写入类"缺 `raw.writes_delta` 计数器，记未测（B 类），不影响镜头 6/7/8。

## 2. 复现命令与结果

```bash
python tools/m3-checks/assert_brail_contract.py <path>/tools/m1-mock/tool_server.py
```

```
B 轨契约闸门（mock vs c9dda83）
  [PASS] G0   四条 READBACK_PENDING 的 details 均非空
  [PASS] G1   details 使用 proposal_status 字段名
  [PASS] G2   applying 路径的 proposal_status = applying
  [PASS] G3   readback_pending 路径的 proposal_status = readback_pending
  [PASS] G4   四条 READBACK_PENDING 的 retryable 均为 true
  [PASS] G5   写前路径含 business_write_count_delta=0
  [PASS] G6   写前路径服务端写入增量 = 0
结论：7/7 项全部通过 → B 轨可开录（仍须 4 条 MOCK 标识）。
GATE_EXIT=0
```

## 3. 关键修复点核对（上一轮唯一未修项）

前次 3 项失败（G0 / G2 / G5）同源于崩溃分支未传 `details`。新文件 `L878-883`：

```python
if take_flag("simulate_applying_crash"):
    STATE["idempotency"][idem] = {"digest": req_digest, "state": "applying", "result": None}
    raise ToolError("READBACK_PENDING", "结果未知，请用同一幂等键重试。",
                    [{"field": "proposal_status", "reason": "applying"},
                     {"field": "business_write_count_delta", "reason": "0"}],
                    retryable=True)
```

即 11-01 我给出的补丁建议被逐字采纳。**5 处** `READBACK_PENDING`（L817 / L824 / L873 / L880 / L928）`details` 现已全非空。

## 4. 动态探测复核（不只静态读码）

### 4.1 `probe_brail_chain.py`（崩溃路径真跑一遍）

```
step6 apply with simulate_applying_crash (Proposal really applying)
  raw: {"error": {"code": "READBACK_PENDING", "message": "结果未知，请用同一幂等键重试。",
        "retryable": true, "details": [{"field": "proposal_status", "reason": "applying"},
                                        {"field": "business_write_count_delta", "reason": "0"}]}}
  writes_delta: 0
step7 same key retry → IDEMPOTENCY_IN_PROGRESS retryable=True
```

→ 镜头 6 需要的三个字段（`code` / `retryable` / `details[proposal_status=applying]`）**在同一响应体里同时可得**，且服务端写入增量为 0。

### 4.2 `probe_brail_pending.py`（`readback_pending` 三态）

| case | 场景 | code | details 关键字段 |
|---|---|---|---|
| A | `readback_mismatch`（写成功、回读未收敛） | `READBACK_PENDING` | `proposal_status=readback_pending`、`delta=0`、`retryable=true` |
| B | 已处于 pending 的提案、换新键重试 | `READBACK_PENDING` | `proposal_status=readback_pending`、`delta=0` |
| C | 同键幂等重放（回读续跑） | `READBACK_PENDING` | `proposal_status=readback_pending`、`delta=0`、`operation=readback_only` |

→ 镜头 7（收敛演示）与镜头 8（零写入）在 `readback_pending` 侧亦成立。

## 5. 开录条件与仍存限制

**已满足**（M0 甲方案）：
1. Mock 4 项偏差全部修齐（闸门机检 7/7）；
2. C 侧同脚本复测通过（本文档）；
3. 8 镜可一次性连续录制，镜头 6 不再标 BLOCKED。

**仍存限制（不因闸门通过而消失）**：
1. **B 轨证据须带 4 条 MOCK 标识**（M0 裁定），录制画面与口播仍需明确"Mock 后端、非真实端点"；
2. **本闸门只判 Mock 行为**，判过不等于真实端点通过；A 轨仍需真实 apply 端点 + 可信用户确认 + 第二账号只读复核；
3. 镜头 7 的"收敛"在 `applying` 崩溃路径上是**如实不收敛**（停在 `applying`、同键 `IDEMPOTENCY_IN_PROGRESS`）——口播按此表述，不得宣称已收敛。

## 6. 证据字段核验（`verify_m1_evidence.py`，严格口径）

```bash
python tools/m3-checks/verify_m1_evidence.py \
  --evidence <e7dd43b1d>:docs/contracts/reviews/m1-evidence-c9dda83.json \
  --contract c9dda83
```

```
证据文件: docs/contracts/reviews/m1-evidence-c9dda83.json（e7dd43b1d）
契约基准: c9dda83（21 个错误码）
结果条目: 35（core 15 + examples 20）
自述通过: 35 / 35

契约冲突: 0
未测 A（READBACK_* 缺必填 raw 字段）: 0
未测 B（零写入类缺计数器，不影响 READBACK_* 行为判定）: 5
  ? T1 跨 Proposal 错绑 Token → APPROVAL_UNTRUSTED: APPROVAL_UNTRUSTED 未给 raw.writes_delta 整数
  ? ORD-1 已应用 + 新键 → ALREADY_APPLIED: ALREADY_APPLIED 未给 raw.writes_delta 整数
  ? already_applied_with_new_idempotency_key: ALREADY_APPLIED 未给 raw.writes_delta 整数
  ? consumed_token_cannot_authorize_another_apply: APPROVAL_CONSUMED 未给 raw.writes_delta 整数
  ? approval_token_expired_before_apply: APPROVAL_EXPIRED 未给 raw.writes_delta 整数
需说明: 2
  ! X2 权威回读不一致 → READBACK_MISMATCH(failed, 零写入): raw.second_apply_executed='false' 是 str，契约示例为布尔
  ! list_tasks_with_recurring_and_one_time: 自述与示例存在差异（fixture/字段）
VERIFY_EXIT=0
```

**A 类（硬缺口）= 0**：6 条 `READBACK_*` 用例（`X1-a` / `X1-1` / `X1-2` / `X1-3` / `X2` / `EX-20=write_may_have_succeeded_but_readback_is_pending`）的 `raw.proposal_status`（取值合法）、`raw.writes_delta`（int）、`raw.retryable`（与示例一致：PENDING=true、MISMATCH=false）、`raw.details`（非空）**四项全齐**。M0 12:54Z 指出的 `X2` / `EX-20` 两处已闭合。

**B 类（软缺口）= 5**：`T1` / `ORD-1` 与 3 条 examples 属"零写入类"，但只给了 `raw.code`、无 `raw.writes_delta` 计数器。**不影响镜头 6/7/8**（这三镜依赖的是 `proposal_status` / `retryable` / `details`），仅使这 5 条的"零写入"结论停在未测。

### 6.1 三条"通过但不能当强证据"的说明（不掩盖）

闸门与字段核验都过，但下面三点仍须写明，否则等于用字段齐全掩盖语义降级：

1. **`X2` 的路径语义被降级**：`raw.path` 写的是 `readback_only`，`steps` 第 1 步却是 `READBACK_PENDING`；M1 邮件说明"用 crash 路径模拟"。即：**并没有真正写入后再回读不一致**，不一致是构造出来的。这条能证明「错误码 + 四个字段的形状正确」，**不能证明「写后回读不一致」这条真实路径**。
2. **`X2` 的 `second_apply_executed` 是字符串 `"false"`**，契约 §4.1 示例 #21 是布尔 `false`。字段语义对、类型不对，记「需说明」不记冲突。
3. **`T1` / `ORD-1` 与 3 条 examples 的零写入无计数器**：不怀疑其结论，但这 5 条**按纪律只能记未测**，不能因为 `pass: true` 就算过。

> 上述三点**不影响 B 轨 8 镜开录**（镜头 6/7/8 依赖的是 `READBACK_*` 的 `code` / `proposal_status` / `retryable` / `details` 与服务端写入增量，这些已具备）。是否需要 M1 再补一轮由 M0 决定；C 侧建议：录制不受阻，这 5 条随 X1/T03-b/Y1 一并记为未测。

## 7. 核验器口径修正（回应 M0 12:54Z）

M0 指出的两处漏洞**成立**，已改，并用反例回归验证：

| 漏洞 | 旧行为 | 现行为 |
|---|---|---|
| `proposal_status` 可从文本回退 | `raw` 缺失时用正则从 `expected/got/note` 提取 | **只读 `raw.proposal_status`**；缺失即记 A 类未测 |
| 零写入识别不按用例类别 | 靠文本出现"零写入"字样触发 | **按错误码集合判定**（`raw.code` 优先，文本仅用于识别该条讲哪个码） |
| `writes_delta` 类型 | 字符串 `"0"` 也可能被接受 | 必须是 `int`（显式排除 `bool`），字符串即记未测 |
| `retryable` | 只查存在 | 与契约示例比对：`READBACK_PENDING=true`、`READBACK_MISMATCH=false`，相反即冲突 |
| `details` | 未检查 | `READBACK_*` 必须为非空数组，且须含 `proposal_status` 条目 |

**反例回归（证明漏判已堵）**：把 `X1-a` 的 `raw.proposal_status` 与 `raw.writes_delta` 删掉、文本仍保留 `proposal_status=applying`：

```
未测 A（READBACK_* 缺必填 raw 字段）: 1
  ? X1-a 消费后崩溃 → READBACK_PENDING（applying, 零写入）: READBACK_PENDING 缺 raw.proposal_status（§4.1 强制；不接受文本回退）
```

旧版此例会被判"字段齐全"。**结论：M0 所担心的"exit 0 掩盖字段缺失"已不可复现。**

## 8. 开录条件与仍存限制

**已满足**（M0 甲方案）：
1. Mock 4 项偏差全部修齐（闸门机检 7/7，exit 0）；
2. 证据 `READBACK_*` 六条字段全齐（A 类 0 缺口）；
3. C 侧同脚本复测通过（本文档 §2–§7）；
4. 8 镜可一次性连续录制，镜头 6 不再标 BLOCKED。

**仍存限制（不因闸门通过而消失）**：
1. **B 轨证据须带 4 条 MOCK 标识**（M0 裁定），录制画面与口播仍需明确"Mock 后端、非真实端点"；
2. **本闸门只判 Mock 行为**，判过不等于真实端点通过；A 轨仍需真实 apply 端点 + 可信用户确认 + 第二账号只读复核；
3. 镜头 7 的"收敛"在 `applying` 崩溃路径上是**如实不收敛**（停在 `applying`、同键 `IDEMPOTENCY_IN_PROGRESS`）——口播按此表述，不得宣称已收敛；
4. B 类 5 条零写入计数器缺失，记「未测」，不升 E1；
5. 分享链接第二账号验证仍 BLOCKED（M1 已确认：链接已生成但取不到 URL）。

## 9. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-11-02 21:55 | 建立；`e7dd43b1d` 闸门 7/7 通过（exit 0）+ 两条动态探测复核，判定镜头 6 解封 |
| 2026-11-02 22:10 | 并入证据字段核验（A 类 0 / B 类 5）；核验器按 M0 意见改为 raw-only + 错误码驱动，并附反例回归 |
