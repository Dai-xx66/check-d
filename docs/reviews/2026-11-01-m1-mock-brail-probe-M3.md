# M1 Mock 的 B 轨可行性实测（契约 c9dda83，mock @ 36ab22e）

- **执行人**：C / M3（钟钰芬）
- **日期**：2026-11-01
- **对象**：`tools/m1-mock/tool_server.py`（M1 分支 `36ab22e`，PR #3 未合并）
- **判据**：当前唯一基准契约 `c9dda83195a9af4b9ca762d8556fdd0e8d43010a` §4.1 + 示例 #21 / #31 / #34 / #45
- **证据级别**：**E1（本机可复现）**。命令见 §5，任何人在同一 mock 上重跑应得到同样结果
- **目的**：回答 M0 的问题「B 轨录制状态」——不是"脚本写好了"，而是"这套 mock 能不能录出脚本要求的画面"

## 1. 结论先行

**B 轨目前不能按原脚本录完镜头 6 / 8。** mock 能跑通整条链路（拆解→校验→审批→写入），但 `READBACK_PENDING` 的响应体与契约不一致，导致分镜镜头 6 的核心断言（`proposal_status` 与真实状态一致）**无法达成**。

| 检查点 | 期望（契约） | 实测（mock 36ab22e） | 判定 |
|---|---|---|---|
| 工具集合 | 7 个 | 7 个（`list_tasks` / `get_calendar_events` / `generate_schedule` / `validate_schedule` / `apply_approved_changes` / `request_approval` / `get_approval_status`） | **PASS** |
| MCP 握手 | initialize + tools/list | `protocolVersion=2024-11-05`，`serverInfo=checkd-agent-mock 0.4.0` | **PASS** |
| 全链路可跑 | list→generate→validate→approve→apply | 4 任务、12 变更、0 violations、审批签 Token、apply 可达 | **PASS** |
| 详情字段名 | `proposal_status`（#21/#31/#34） | `proposal.status` | **FAIL** |
| `retryable` | `true`（#21/#31/#34 全部） | 预存非终态路径 `false`；crash 路径 `true` —— 同码不同值 | **FAIL** |
| `applying` 分支值 | `proposal_status=applying`（#31） | 预存 applying 时返回 `readback_pending`；crash 路径 `details=[]` | **FAIL** |
| 零写入明细 | `business_write_count_delta=0`（#21/#31/#34） | 三处均无此条 | **FAIL** |
| 崩溃路径收敛 | 同键重试可收敛 | 永远 `IDEMPOTENCY_IN_PROGRESS` | **FAIL**（仅影响镜头 7/8） |

## 2. 三条 `READBACK_PENDING` 路径的实测响应

运行环境：Windows + CPython，`CHECKD_TOKEN=demo-token-alice`，审批库与测试开关均指向临时文件（不污染仓库）。

### 2.1 写后崩溃（`simulate_applying_crash`）——Proposal 真实状态 = `applying`

```json
{"error": {"code": "READBACK_PENDING", "message": "结果未知，请用同一幂等键重试。",
           "retryable": true, "details": []}}
```

- `details` 为**空数组**：既没有 `proposal_status`，也没有 `business_write_count_delta`；
- 服务端写入计数增量 **0**（正确：崩溃发生在写入前）；
- 同键重试：`IDEMPOTENCY_IN_PROGRESS`（409，`retryable=true`），**连续两次均如此，不收敛**。

→ 这正是契约示例 **#31** 的场景（新键 + applying → `proposal_status=applying`），而 mock 在这里**什么状态都不给**。

### 2.2 写后回读未收敛（`readback_mismatch`）——Proposal 真实状态 = `readback_pending`

```json
{"error": {"code": "READBACK_PENDING", "message": "写入可能已提交但回读未完成。",
           "retryable": false,
           "details": [{"field": "proposal.status", "reason": "readback_pending"}]}}
```

- 值 `readback_pending` **恰好正确**（真实状态就是 readback_pending），但**字段名是 `proposal.status`**，契约要求 `proposal_status`；
- `retryable=false`，契约 #21/#34 均为 `true`；
- 服务端写入计数增量 **12**（=本次 changes 条数，写入确实发生，符合该路径语义）；
- 同键重试：**返回成功**（`readback_verified=true`）→ 该路径可以演示"收敛"。

### 2.3 预存非终态 + 新幂等键

```json
{"error": {"code": "READBACK_PENDING", "message": "写入可能已发生，只能用同一幂等键继续回读。",
           "retryable": false,
           "details": [{"field": "proposal.status", "reason": "readback_pending"}]}}
```

- 与 §2.2 同样的字段名与 `retryable` 问题；
- 值恒为 `readback_pending`（硬编码），**若 Proposal 实际处于 `applying` 也会报 `readback_pending`** → 契约 §4.1"必须反映真实状态"无从满足。

## 3. 对 B 轨录制的直接影响

| 分镜镜头 | 原脚本要求 | 能否录 | 说明 |
|---|---|---|---|
| 1–5 | 工具 7/7、只读调用、拆解、violations、确认面板 | **可录** | 实测链路全通，`request_id`/`trace_id` 均返回 |
| **6** | `READBACK_PENDING` 详情 `proposal_status` 与真实状态一致 | **不可录** | 字段名不符 + applying 分支无值 → 录出来就是违反脚本自己的断言 |
| 7 | 回读一致 | **部分** | 走 readback_pending 路径可收敛；crash 路径永远 409 |
| 8 | 重复请求零写入 | **可录**（`IDEMPOTENCY_IN_PROGRESS` + 计数 0） | 但"新键 → 零写入"拿不到 delta 明细字段 |

**因此 B 轨的"关卡自检第 6 条"（`proposal_status` 与真实状态一致）当前只能标 `BLOCKED`**，不得因为"脚本里写了该字段"就记为通过——这与 M0 裁定四一致。

## 4. 给 M1 的最小修改建议（4 处，均在 `tool_server.py`）

1. **统一字段名**：三处 `{"field": "proposal.status", ...}` → `{"field": "proposal_status", ...}`；
2. **按真实状态取值**：预存分支不再硬编码 `readback_pending`，改为 `p["status"]`（`applying` / `readback_pending`）；
3. **补 `retryable=true`**：预存分支当前把 details 当作第 3 个位置参数，`retryable` 默认 `false`，需显式传入；
4. **补零写入明细**：预存分支与 crash 分支补 `{"field": "business_write_count_delta", "reason": "0"}`（#21/#31/#34 均有此条）。

可选（不阻塞）：崩溃路径增加"下一次同键重试收敛到 `applied` 或 `failed`"的状态迁移，否则镜头 7 的"终局收敛"只能走 readback_pending 路径。

## 5. 复现命令

```bash
# 取 mock（不进我们分支，只在临时目录展开）
d=$(mktemp -d) && git archive 36ab22e tools/m1-mock | tar -x -C "$d"

# 链路探测（含 crash 路径，打印 details 与写入计数增量）
python tools/m3-checks/probe_brail_chain.py "$d/tools/m1-mock/tool_server.py"

# 回读未收敛路径（含同键重试收敛）
python tools/m3-checks/probe_brail_pending.py "$d/tools/m1-mock/tool_server.py"
```

两个脚本只读：不调用任何写接口以外的工具、不修改仓库、审批库与 flag 文件都落在 `mktemp` 目录；`writes` 计数直接读 mock 自己维护的 flag 文件，因此"写入增量"是**服务端自记**而非客户端自述。

## 6. 证据边界

- 本记录证明的是 **mock 的行为**，不证明真实服务行为；
- 不构成对 M1 实现能力的否定：链路本身跑通了，问题集中在 `READBACK_PENDING` 的响应细节；
- B 轨录屏仍属 **Mock 演示**，不得表述为真实写入闭环（M0 裁定一）；
- X1 / T03-b / Y1 的证据状态**不因本次实测改变**，仍为「未测」。
