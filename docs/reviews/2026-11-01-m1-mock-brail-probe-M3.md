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

## 7. 复测闸门（M0 选定甲方案后新增）

M0 于 2026-11-01 12:46 邮件裁定采纳**甲方案**：M1 修 4 处 → C 用同一探测脚本复测 → 全通过才录 8 镜。为让"通过"可机器判定，新增闸门脚本：

```bash
python tools/m3-checks/assert_brail_contract.py <path>/tools/m1-mock/tool_server.py
# exit 0 = 通过，可开录；exit 1 = 不通过，镜头 6 保持 BLOCKED
```

闸门在同一 MCP 会话内跑四个 `READBACK_PENDING` 场景，逐项判定：

| 闸门 | 判据 | 对应 M0 要求 |
|---|---|---|
| G1 | `details` 字段名为 `proposal_status` | 第 1 项 |
| G2 | `applying` 路径（崩溃后 + 预存）值均为 `applying` | 第 2 项 |
| G3 | `readback_pending` 路径值均为 `readback_pending` | 第 2 项 |
| G4 | 四条响应 `retryable=true` | 第 3 项 |
| G5 | 写前路径 `business_write_count_delta=0` | 第 4 项 |
| G6 | 写前路径服务端写入增量 0（无第二次 apply） | 第 4 项后半 |

**当前基线（mock `36ab22e`）：4/6 不通过**，G1/G2/G4/G5 FAIL、G3/G6 PASS。四个场景的原始响应：

| 场景 | Proposal 真实状态 | `details` 实测 | `retryable` | 写入增量 |
|---|---|---|---|---|
| 崩溃后 + 旧键 | `applying` | `[]`（空） | `true` | 0 |
| 回读未收敛 | `readback_pending` | `[{"field":"proposal.status","reason":"readback_pending"}]` | `false` | 12 |
| 预存 pending + 新键 | `readback_pending` | 同上 | `false` | 0 |
| 预存 applying + 新键 | `applying` | 同上（值应为 `applying`） | `false` | 0 |

注意最后一行：Proposal 真实处于 `applying`，Mock 仍返回 `readback_pending` —— 与 B20 当初指出的"值不反映真实状态"是同一类问题，只是这次落在实现而非契约。

**闸门通过后的动作**：一次性录 8 镜（§6.3 归档），仍须满足 4 条 MOCK 标识；闸门通过只代表 Mock 行为合契约，不代表真实端点通过。

## 8. 复测结果：mock `1d4f3f2`（2026-11-01 22:41Z 邮件后实跑）

**结论：4 项修复到位 3 项；崩溃路径（`simulate_applying_crash`）仍不合契约 → 闸门 4/7 通过（3 项不通过），镜头 6 继续 BLOCKED。**

外部核实：PR #3 状态 `open`/未合并，`head_sha = 1d4f3f2964e457933df48de8b0c2ca751e4296a9`（与邮件自述一致）；`36ab22e..1d4f3f2` 仅动 M1 自有文件（`tool_server.py`、`run_evidence_c53.py`、两份证据），无越界。

### 8.1 逐项对照

| 闸门 | 判据 | 旧 `36ab22e` | 新 `1d4f3f2` | 说明 |
|---|---|---|---|---|
| G0 | 四条 `READBACK_PENDING` 的 `details` 均非空 | FAIL | **FAIL** | `crash_applying` 返回 `details: []` |
| G1 | 字段名 = `proposal_status` | FAIL（`proposal.status`） | **PASS** | 三处已改；空 details 不参与本项判定 |
| G2 | `applying` 路径值 = `applying` | FAIL | **FAIL** | 预存路径已修好（`applying`）；崩溃路径无值 |
| G3 | `readback_pending` 路径值 = `readback_pending` | PASS | PASS | 两条均正确 |
| G4 | 四条 `retryable=true` | FAIL（3 条 false） | **PASS** | 四条均 true |
| G5 | 写前路径含 `business_write_count_delta=0` | FAIL | **FAIL** | 崩溃路径缺失；另两条已补 |
| G6 | 写前路径服务端写入增量 = 0 | PASS | PASS | 崩溃路径与两条新键路径 `writes_delta` 实测均为 0 |

合计：旧 5/7 不通过 → 新 **3/7 不通过**，且 3 项同源于一处：崩溃路径未传 `details`。

### 8.2 唯一剩余缺陷（一处，位置明确）

`tools/m1-mock/tool_server.py` L862-866：

```python
p["status"] = "applying"
if take_flag("simulate_applying_crash"):
    STATE["idempotency"][idem] = {"digest": req_digest, "state": "applying", "result": None}
    raise ToolError("READBACK_PENDING", "结果未知，请用同一幂等键重试。", retryable=True)
```

此处 Proposal 已被置为 `applying`，但 `ToolError` 第三个位置参数（`details`）未传 → 响应 `details: []`。按 c9dda83 §4.1 与示例 #31，此时必须：

```python
raise ToolError("READBACK_PENDING", "结果未知，请用同一幂等键重试。",
                [{"field": "proposal_status", "reason": "applying"},
                 {"field": "business_write_count_delta", "reason": "0"}],
                retryable=True)
```

一处改动即可同时消掉 G0 / G2 / G5 三项失败。**这是 `applying` 分支的唯一实测样本**：其余三支真实状态都不是 `applying`，所以此前"新键遇到 applying 返回 applying"的修复虽已生效，却没有一条路径能验证它——崩溃路径就是那条路径。

### 8.3 随附证据核验（`m1-evidence-c9dda83.json`）

`python tools/m3-checks/verify_m1_evidence.py --evidence 1d4f3f2:docs/contracts/reviews/m1-evidence-c9dda83.json --contract c9dda83`

- 34 条（core 14 + examples 20），自述 34/34；**契约冲突 0**（错误码全在 21 码闭集内）。
- **3 条证据不足**：
  1. `X1-a 首次写入` 无 `raw`，未记录 `proposal_status` → 不可判定；
  2. `T3 applying 同键` 无 `raw`，且 `got` 为 `READBACK_PENDING -> IDEMPOTENCY_IN_PROGRESS` 两步序列；
  3. `X1-2 同键只读` 有 `details` 但无独立 `writes_delta`，零写入仅由响应自述。
- **正面**：`X1-1`、`X1-2`、`X2` 三条均有 `raw`，`proposal_status` / `business_write_count_delta` / `operation` / `second_apply_executed` 字段名与取值正确；`X1-1` 另有 `writes_delta: 0`。
- **结构性缺口**：14 条核心结果中**没有任何一条**的 `proposal_status` 为 `applying`，与 §8.2 的实测缺陷互相印证——证据集覆盖不到崩溃后状态。

### 8.4 处置

镜头 6 保持 **BLOCKED**，不录、不标 PASS（依 M0 2026-11-01 04:46Z 裁定）。M1 补 §8.2 一处 + `X1-a`/`T3` 的 `raw` 后，重跑：

```bash
python tools/m3-checks/assert_brail_contract.py <新mock>/tool_server.py   # 需 exit 0
```

闸门全绿才开录 8 镜。

## 9. M0 裁定（2026-11-01T15:11Z）与证据清单

M0 采纳 C 侧复测结论，明确「M3 的结论优先于 M1 自报的 14/14 与 20/20；当前闸门未全绿，完整 8 镜暂不录制」，并分三档：

| 档 | 内容 | 归属 |
|---|---|---|
| 一 | 修 L862-866 崩溃分支：`details.proposal_status=applying`、`business_write_count_delta=0`、`retryable=true`；不得二次 apply、业务写入增量必须 0；**不得硬编码 `readback_pending`**；不得动 M0 契约或 M2/M3 文件 | M1 |
| 二 | 与 C 对齐证据清单，补齐 `X1-a`、`T3` 原始响应、`X1-2` 独立 `writes_delta`；无 `raw` 继续标未测，禁止按摘要推 PASS | M1 + M3 |
| 三 | 拿到新 SHA 后用**同一探测脚本**复测；全绿（exit 0）才录 8 镜，任一失败 → 镜头 6 继续 BLOCKED 并报差异；录制保留 MOCK 片头与全程角标 | M3 |

关于「不得硬编码 `readback_pending`」：本闸门 **G2 已是该约束的判据**——`applying_newkey` 场景在 Proposal 真实状态为 `applying` 时，若返回值仍是 `readback_pending` 即 FAIL（旧 `36ab22e` 正是如此）。故不新增冗余闸门，G2 继续承担这条。

证据清单已按字段级口径落地：**`docs/reviews/2026-11-02-m1-evidence-checklist-M3.md`**，含每条的必填字段、JSON 样例、两条格式纪律（禁止 `A -> B` 箭头、fixture 差异须在 `note` 声明）与提交前自检命令。
