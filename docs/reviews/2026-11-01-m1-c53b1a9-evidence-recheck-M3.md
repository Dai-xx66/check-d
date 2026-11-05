# M1 证据独立核验（`36ab22e` @ 契约 `c9dda83`）— M3 / C 侧

- **核验对象**：A / M1 的 `docs/contracts/reviews/m1-evidence-c53b1a9.json`（32 条）与 `m1-workbuddy-live.json`（9 条），提交 `36ab22e`（PR #3 head，`open`/未合并，API 核实）。
- **核验口径**：**不采信其 `pass` 标志**，只核事实字段能否支撑结论（C 侧纪律：自述 ≠ 证据）。
- **结论**：**0 条契约冲突**；但 **4 条证据不足、2 条需说明**，因此 X1 / T03-b / Y1 **本轮不能升实测 E1**，矩阵中仍记「未测」。

## 0. 结果总览

| 指标 | 值 | 说明 |
|---|---|---|
| 结果条目 | 32（core 12 + examples 20） | 另实机 9 条（W1–W9） |
| 自述通过 | 32 / 32 | A 的 `pass`/`status` 标志，仅作参考 |
| **契约冲突** | **0** | 所有错误码均在 21 码闭集内；无越界值 |
| 可核 PASS | 28 | 字段充足、语义与 c9dda83 一致 |
| 其中"干净可核" | 26 | 另 2 条带说明项（T2、EX-01），见 §2 |
| **证据不足** | **4** | 全部是缺 `proposal_status`，见 §1 |
| 需说明 | 2 | T2 的 `->` 序列、EX-01 的 fixture 差异 |

命令（可复现，退出码 0）：

```
python tools/m3-checks/verify_m1_evidence.py \
  --evidence 36ab22e:docs/contracts/reviews/m1-evidence-c53b1a9.json \
  --contract c9dda83
```

## 1. 证据不足（4 条，全部同一根因）

| 用例 | 缺什么 | 为什么这会卡住结论 |
|---|---|---|
| `X1-a 首次写入 → READBACK_PENDING` | `raw` 为空，无 `proposal_status` | c9dda83 的 §4.1 要求 `READBACK_PENDING` 详情必须含 `proposal_status` 且**反映真实状态**；未记录则该断言无据可判 |
| `X1-1 新幂等键 → READBACK_PENDING 且零写入` | 只有 `writes_delta=0`，无 `proposal_status` | 同上；且无法区分是「新键 + `applying`」还是「新键 + `readback_pending`」两条不同路径 |
| `T3 applying 同键 → IDEMPOTENCY_IN_PROGRESS` | 同上 | 该用例先用一次 apply 进入 `applying`，其响应即 `READBACK_PENDING`，正好落在这条新规上 |
| `write_may_have_succeeded_but_readback_is_pending`（示例·写后未知） | 同上 | 同属 `READBACK_PENDING` 家族 |

**影响**：矩阵 §3C.4 刚把 X1 / T03-b / Y1 由"容忍两值"收紧为"按路径定值"（`applying` 路径必须为 `applying`）。A 的记录没有这个字段，**无法证明其实现返回的是正确的那一个**。这不是说他错，而是"证据不足以判定"——按纪律不得升级。

**最小补正**（一次导出即可）：在 X1-a、X1-1、T3、写后未知 四条的 `raw` 里加上 `proposal_status` 与 `path`（`new_key+applying` / `new_key+readback_pending` / `same_key+readback_pending`），重导 `m1-evidence-*.json`，我重跑同一条命令即可定性。

## 2. 需说明（2 条）

| 用例 | 现象 | 待澄清 |
|---|---|---|
| `T2 failed+已消费 → APPROVAL_CONSUMED` | `got` 为 `PROPOSAL_INVALID -> APPROVAL_CONSUMED` | 是"先用管理路径把 Proposal 置为 failed，期间返回 PROPOSAL_INVALID，再触发目标用例"的两步语义，还是"第一次跑失败、修完后重跑通过"？后者不能算单次运行证据（本表纪律：一条记录对应一次运行） |
| `list_tasks_with_recurring_and_one_time`（EX-01） | 自述 `mock tasks=4 vs example=2 (fixture differs)` | 差异已主动声明，值得肯定；但该条**只能证明"信封与键名一致"**，不能作为示例级一致性证据，判读时需降档 |

`T3` 的 `READBACK_PENDING -> IDEMPOTENCY_IN_PROGRESS retryable=True` 属正常两步（第一次 apply、第二次同键重试），不算问题，仅需在说明里写明步骤编号。

## 3. 实机证据（W1–W9）

| 用例 | 状态 | C 侧判读 |
|---|---|---|
| W1 自定义 stdio MCP 注册 | pass | 7/7 工具加载，与契约 7 工具一致（E1 我方复核记录，非 E2） |
| W2 真实工具调用 | pass | `request_id=c0c500ff…`、`trace_id=trace_e0de08…`、返回 4 条任务；**内部 `call_*` 只在本地日志** |
| W3 工具调用 ID 是否暴露给模型 | **fail** | 与 A 自述一致：模型只拿到业务 `trace_id`。作为**已知限制**接受，但代价是证据链只能到 trace 级 |
| W4 远程 HTTPS MCP | blocked | 未做 |
| W5 第二账号 / 分享链接只读调用 | blocked | D9 的核心关卡，仍未做 |
| W6 可信用户确认信号 | blocked | 连接级"信任"，无身份/时间/防重放——直接决定"审批后写入"能否算真实闭环 |
| W7 初始化超时 | pass | 30s 设定 / 观测 30028ms |
| W8 不可达 | pass | MCP error -32000 |
| W9 401 | pass | 业务码 `AUTH_REQUIRED retryable=false`，MCP 层不透出 HTTP 状态码 |

**证据质量瑕疵（1 项）**：`artifacts` 中 `list-call.png` 与 `call-result.png` 的 SHA-256 **完全相同**（`05a6a5cc…`），即同一张图被命名两次。两张截图因此**不能互相独立佐证**"列表调用成功"与"调用结果"。建议补一张真正独立的截图，或在文件清单里标注为同一画面的两种截取。

**证据级别**：实机部分最高给 **E1**（我方对照其字段与哈希复核），**不给 E2**——`call_*` 级不可外部复核，第二账号/可信确认均未做，无法在他人环境复现。

## 4. 与 D4 的关系（今日关卡）

D4 的关卡是"第一条可完整复现的真实 Agent 闭环（拆解→确认→写入→回读）"，其前置条件恰是 W4/W5/W6 三条 blocked：真实 apply 端点、第二账号只读复核、可信用户确认。因此：

- **今日可交付**：录屏分镜与 Mock 轨演示（`docs/demo/d4-recording-storyboard.md`），明确标注 MOCK，不宣称真实写入。
- **今日不可交付**：真实写入闭环录屏（缺 M0 的 apply 后端 + 可信确认）。
- 一旦 M0 打通，用同一份分镜直接录 A 轨，不需要重写脚本。

## 5. 附：核验脚本的口径局限

`verify_m1_evidence.py` 只检查"记录是否足以支撑结论"，**不判断实现正确性**。它能抓出：错误码越界、`READBACK_*` 缺状态、`writes_delta≠0`、`->` 序列未说明、自述差异。它抓不出：状态机分支是否真的可达（需执行）、并发行为、写计数是否被篡改（需代码审计）。
