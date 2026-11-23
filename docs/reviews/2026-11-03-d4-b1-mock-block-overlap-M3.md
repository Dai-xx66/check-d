# D4-B1（缺陷）：提案块之间重叠，`validate_schedule` 不报

- **发现人**：M3（钟钰芬）
- **发现时间**：2026-11-03 11:40（本地）/ 03:40Z
- **被测对象**：`Tony2215/check-d` @ `e7dd43b1dc28b0fb239a78c8335d761df15449db`（PR #3 head），`tools/m1-mock/tool_server.py`，sha256 `0ff37fe2940cdfe3e0983191b5ddc2461f866eb56ae1a33da306315d71c0b86f`
- **性质**：B 轨录制前的画面级阻断（不影响写入链路，见 §5）
- **级别**：P1（演示不可用；且是「提案内容正确性」零覆盖）

## 1. 现象

一次 `generate_schedule`（默认参数、不传任何 preferences，排除调参导致）在 2026-10-29 ~ 11-01 窗口内排出 10 个块，其中 **6 对时间重叠**：

```
t_1001  2026-10-29 09:40 -> 11:10
t_1002  2026-10-29 09:40 -> 10:40   ← 与上一条完全重叠
t_1003  2026-10-29 09:40 -> 10:10   ← 同上
t_1004  2026-10-29 09:40 -> 10:40   ← 同上
t_1003  2026-10-30 08:00 -> 08:30
t_1004  2026-10-30 08:00 -> 09:00   ← 重叠
（10-31、11-01 同形）
```

随后 `validate_schedule` 返回：

```
validation_status = valid
approval_status   = pending_approval
violations        = []
```

即**四个任务被同时压在 09:40，校验却说「合法、可进审批」**。

## 2. 复现（两条命令）

```bash
python tools/m3-checks/demo_driver.py --mock <e7dd43b1d>/tools/m1-mock/tool_server.py
# 输入 2 看只读，输入 3 看提案（画面即上表），输入 4 看校验（valid / violations 0）
```

脚本内置窗口 `2026-10-29 ~ 2026-11-01`；默认 preferences 同样复现（第 1 节数字即默认参数结果）。

## 3. 根因（代码级，可指到行）

1. `schedule()` 里 `busy` 只由 **固定事件** 构成：

```python
busy = sorted((... for e in fixed if e["date"] == d.isoformat()))
```

2. 每放一个块后，**没有把它写回 `busy`**，所以下一个任务仍然从 `day_start`（或固定事件之后）开始找第一个空档 → 每个任务都落在同一个起点。
3. `check_hard_constraints()` 只做「块 vs 固定事件」比对（`FIXED_EVENT_CONFLICT`），**没有块 vs 块的重叠检查**：

```python
for e in events:
    if not e["fixed"] or e["date"] != b["start_at"][:10]:
        continue
    ...
```

4. 契约的违反码是 7 值闭集：`BLOCK_TIME_INVALID` / `FIXED_EVENT_CONFLICT` / `MULTIPLE_BLOCKS_FOR_RECURRING_TASK_DAY` / `MULTIPLE_CHANGES_FOR_ONE_TIME_TASK` / `PLANNED_BEFORE_AVAILABLE_FROM` / `PLANNED_AFTER_DATE_ONLY_DEADLINE` / `BLOCK_AFTER_EXACT_DEADLINE`。
   **闭集里没有「块间重叠」这一码**，所以即便想报也报不出来 → 这同时是契约侧缺口，需要 M0 定：新增码（如 `BLOCK_OVERLAP`）还是并入既有的 `BLOCK_TIME_INVALID`。

## 4. 影响

| 面 | 影响 |
|---|---|
| D4 录制镜头 3/4 | **阻断**。画面会显示 4 个任务同时压在 09:40，且校验说 `valid` —— 与「排期合理、冲突要说清」的叙事直接矛盾，任何评审都会一眼看出 |
| 写入链路（镜头 5–8） | **不受影响**，已实测全 PASS（见 §5） |
| 契约断言（闸门 G0–G6、证据 A/B 类） | 不涉及，B 轨闸门 7/7 仍成立 |
| D6 调度测量 | 不受影响：D6 测的是 M2 的 Dart 引擎（`0f87d4431`），场景 C 实测块间重叠 0；本缺陷在 M1 的 Python mock 里 |

## 5. 与写入链路无关的证据（同一驱动、同一进程，8 镜实测）

```
镜 5  request_approval      -> status=pending，approval_token=(none)
镜 5a 外部审批页 approved    -> status=approved，approval_token=tok_c563********dd4a（已打码）
镜 6  apply(simulate_applying_crash)
            -> code=READBACK_PENDING / retryable=True
               details.proposal_status=applying
               details.business_write_count_delta=0
               服务端写入计数 delta=0                      [PASS]
镜 7  list_tasks 回读        -> 逐条一致 4/4，写入计数 0
镜 8  同键重试               -> IDEMPOTENCY_IN_PROGRESS，delta 0
       换新键                 -> READBACK_PENDING，proposal_status=applying，delta 0
```

## 6. 修复建议（3 行 + 1 个契约决定）

**Mock 侧**：把已放置的块并入当天的 `busy`，再找下一个空档：

```python
# 放块成功之后，紧跟一行（one_time 与 recurring 两处各一次）
busy = sorted(busy + [(_hm(bs), _hm(be))])   # 或维护 day_busy[d].append(...)
```

**校验侧**：`check_hard_constraints()` 增加块间重叠检测（排序后相邻块比较，$O(n\log n)$）。

**契约侧（需 M0 定口径）**：块间重叠用哪个码？现闭集 7 值无法表达。建议新增 `BLOCK_OVERLAP`，因为它与 `BLOCK_TIME_INVALID`（单块时间非法）、`FIXED_EVENT_CONFLICT`（块与固定项冲突）语义不同，合并会让「冲突要说清哪一条」变得含糊。

## 7. 我没有做的事（边界）

- **没有改 M1 的代码**：`tools/m1-mock/` 不在 PR #1 分支，也不应由 M3 代改；本文件只给复现与建议。
- **没有为了画面干净去调参数或挑窗口**：任意窗口、默认参数都复现，属实现缺陷而非配置问题。
- 未测：真实端点（A 轨）；MCP 信封在 WorkBuddy 平台侧的表现。

---

编制：钟钰芬（C / M3）｜2026-11-03

## 8. 追加：8757c0e 复测（2026-11-03，PR #3 最新 head）

M1 当日推送 `8757c0e5542f9c11b73f6933bf2683ca01082334`（EX-15/17/18 计数器 + 生成器
`strict_bool`），本轮复测确认**本报告的 P1 未被触碰**：

- `tools/m1-mock/tool_server.py` sha256 前 16 位 `0ff37fe2940cdfe3`，与 `e7dd43b1d` **字节相同**；
- 实测 `generate_schedule`：10-29 四块同起点 09:40；块间重叠 **9 对**（10-29 六对 + 10-30/31、11-01 各一对）；
- 实测 `validate_schedule`：`validation_status=valid` / `violations=0`。

因此 8 镜录制的内容级阻塞仍然成立：开录会把「四块堆在同一时刻、校验器说没问题」录进镜头 3 与镜头 4。
修复仍按 §5 的两处补丁；`BLOCK_OVERLAP` 是否入闭集由 M0 定。
