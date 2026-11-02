# M3 复测：M1 `e7dd43b1d` B 轨契约闸门（G0–G6）

- **复测人**：M3（钟钰芬）
- **时间**：2026-11-02 21:55（本地）/ 13:55Z
- **被测对象**：`Tony2215/check-d` @ `e7dd43b1d`（PR #3 head，分支 `review/m1-contract-v1`），文件 `tools/m1-mock/tool_server.py`（1111 行）
- **基准契约**：`c9dda83`（B20 修复后的统一基准）
- **复测性质**：M0 甲方案的验收条件（"C 用同一探测脚本复测，全部通过后才一次性录完整 8 镜"）
- **前次基线**：`1d4f3f2` → 3/7 不通过（`docs/reviews/2026-11-01-m1-mock-brail-probe-M3.md` §8）

## 1. 结论（一句话）

**闸门 7/7 全部通过，exit 0 → 镜头 6 解封，B 轨 8 镜可一次性开录。**

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

## 6. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-11-02 | 建立；`e7dd43b1d` 闸门 7/7 通过（exit 0）+ 两条动态探测复核，判定镜头 6 解封 |
