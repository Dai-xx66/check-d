# M1（WorkBuddy）评审反馈 · `agent-api-v1.md` v1 CANDIDATE

评审人：M1 模块负责人（WorkBuddy / 工具编排）
对象：`Dai-xx66/check-d` 分支 `feat/m0-api-contract` 的 `docs/contracts/agent-api-v1.md`（v1 CANDIDATE）
证据：`m1-evidence.md`（MCP stdio mock，A0–A25，**26/26 通过**）
状态：PR #3 已按 B/C 联合评审完成契约一致性修复；**暂不合并**，等待 M0 最终确认。

> 边界声明：本评审只覆盖 MCP Server 与本地契约流程；**WorkBuddy 实机能力（stdio、env token、确认回调、外部分享）仍为 BLOCKED**，mock 通过不构成平台能力证明。旧 18/18 为历史证据，本版为新 HEAD 重跑结果。

---

## 1. 可以保留的设计

1. **五工具边界**：读（`list_tasks` / `get_calendar_events`）、提案（`generate_schedule` / `validate_schedule`）、写（`apply_approved_changes`）分工清楚。
2. **`api_version` / `request_id` / `timezone` 信封**：已落成可解析 schema（含 `$defs`，见 A25）。
3. **请求体禁止 `user_id`**：mock 用 `INVALID_ARGUMENT` 拒绝（A2）。
4. **`query_version` 与 `base_version` 分离**：`validate`/`apply` 都重算摘要，快照变化返 `SNAPSHOT_CONFLICT`（A19）。
5. **`generate_schedule` 不收客户端 tasks/courses**：A6 拒绝。
6. **`schedule_one_time` 只回读 `planned_date`/`scheduled_at`**：A13 覆盖。
7. **`readback_verified` 必须为 true**：A13/A24 覆盖。
8. **§8 数据最小化与 §9 BLOCKED 清单**：保留。

---

## 2. 必须修改（P0）

### P0-1　身份：WorkBuddy 没有“每用户已验证身份”的透传通道

契约 §4/§8 要求“已验证凭证”。WorkBuddy 的 MCP 只有静态 `headers`/`env` token 或 OAuth 连接，**没有把终端用户身份传给工具的机制**；stdio 下只能靠 `env`。

**建议**：v1 写明 `auth_mode=static_bearer_demo`（一人一 token，服务端 token→user），材料中披露“非终端用户 SSO”。**不要**把 `user_id` 放进请求体。

### P0-2　确认/审批：五工具里没有“人确认”的入口

§7.1 说不新增接口，但又要求 `approval_token` 由可信审批服务签发，二者矛盾。建议两个候选扩展（**是否写入 v1 待 M0 最终确认，不预设 v1.1**）：

- `request_approval(proposal_id)`：只创建 **pending** 审批请求，返回 `approval_id` + `approval_url`；**不返回 token、不构成确认**；按提案幂等（A10）。
- 用户在工具之外（H5/飞书卡片）确认，审批服务标记 approved。
- `get_approval_status(approval_id)`：pending 时无 token；approved 后签发一次性 token；已签发后再轮询返回 `approved + token=null`（A11/A12）。

### P0-3　工具入参缺机器可读 schema

已提供 `docs/contracts/tools.candidate.json`（**candidate，未冻结**，由 `export_schema.py` 生成）。修复后 `$ref` 可解析（`$defs.date_range`），各对象层 `additionalProperties:false`，与 `tools/list` 逐字段一致（A25）。

---

## 3. 联合评审问题的处理结果

### 3.1 已修复并有回归用例

| 来源 | 问题 | 修复 | 用例 |
|---|---|---|---|
| C | `ALREADY_APPLIED` 因判定顺序不可达 | 已应用判定提前到快照重算之前；**现在可达** | A15 |
| C | `APPROVAL_REQUIRED` 一码三义 | 仅保留“缺少凭据”；状态问题→`PROPOSAL_NOT_APPROVABLE`；过期→`PROPOSAL_EXPIRED` | A8/A18 |
| C | 幂等摘要含 token 前缀 | 改为绑定 `approval_id` | A14/A16 |
| C | 审批与提案状态联动；过期提案不得建审批 | 已应用/未校验/过期分别拒绝；审批有效期 30 分钟且不跨当日 23:59 | A18 |
| C | 同一 Proposal 重复 request 幂等 | 复用既有 `approval_id` | A10 |
| C | 第三态（已签发后轮询） | `approved + token=null` | A12 |
| B | `$defs` 缺失导致 schema 不可解析 | 补 `$defs.date_range`（含日期 pattern） | A25 |
| B | `preferences` 注入冲突事件会失效 | 删除该注入；边界状态改由**测试专用 flag 文件**构造，请求 schema 保持闭合 | A22 |
| B | `deadline_key` 把 `date_only` 拼成即时 | 排序只按 `(kind, 值)`，不再合成时间串 | A5 |
| B | 周期任务忽略 `duration_target_seconds` | 按目标时长排块并标 `duration_source=task_target`；无目标才估算 | A5 |
| B | `validate` 不重算 `input_digest` | `validate`/`apply` 均重算，变化→`SNAPSHOT_CONFLICT` | A19 |
| B | 事项不存在时 `KeyError` 崩溃 | 存在性校验返回 `NOT_FOUND` | A20 |
| B | 单日例外回读未覆盖 | 写入后回读 override 分钟数 | A13 |
| C | `readback_pending` 零覆盖 | 回读失败标 pending；同幂等键只重试回读、不二次写入 | A23/A24 |
| B | `unplanned_tasks` 缺 reason 枚举 | 固定 `reason_code`：`no_free_slot` / `insufficient_window` | A5 |

### 3.2 代码层已定，但需 M0/M2 冻结

- **`explanations` 形状**（字符串数组 vs 对象数组）：mock 暂用字符串数组，**未擅自改**；请 M0/M2 给结论后一次性对齐。
- **新增错误码写入契约 §4.1**：`APPROVAL_REQUIRED`、`APPROVAL_UNTRUSTED`、`PROPOSAL_NOT_APPROVABLE`、`PROPOSAL_EXPIRED`、`ALREADY_APPLIED`、`SNAPSHOT_CONFLICT`、`READBACK_MISMATCH`、`IDEMPOTENCY_CONFLICT` 目前只在 mock 与本文档定义，**契约本体未改**（M1 不应改 M0 分支）。
- **`APPROVAL_CONSUMED` 不再作为独立错误码**：`consumed` 状态仍记录在 token 上，但重复 apply 统一返回可达的 `ALREADY_APPLIED`，避免再产生不可达码。

### 3.3 明确未修复（BLOCKED / 未覆盖）

- token **无签名、无 TTL**；审批文件**无访问控制**；**确认者身份未验证** → 保持 BLOCKED。
- 审批级过期（`APPROVAL_EXPIRED`）**未单测**：当前只覆盖提案级过期。
- 真实快照服务、事务内版本比较、原子批量写入、Supabase RLS → BLOCKED。

---

## 4. 测试矩阵（A0–A25，26/26）

| 需求 | 用例 |
|---|---|
| tools/list 与候选 schema 一致、`$ref` 可解析、闭合对象 | A0 / A25 |
| 身份与越权 | A2 / A3 / A17 |
| 日历与外部固定事件 | A4 |
| 提案生成规则（deadline 不伪造、周期时长、排序） | A5 |
| 远程不得提交 tasks/courses | A6 |
| 校验与状态机 | A7 / A21 / A22 |
| 未审批不得写入 | A8 |
| 审批占位：pending、幂等、外部确认、第三态 | A9 / A10 / A11 / A12 |
| 原子写入与回读（单次 + 单日例外） | A13 |
| 幂等重放与冲突 | A14 / A16 |
| 重复 apply 可达错误码 | A15 |
| 过期提案 | A18 |
| 快照冲突 | A19 |
| 事项存在性 | A20 |
| 回读失败与恢复 | A23 / A24 |

判定口径：**响应码 + 状态 + 数据 + 实际写入次数**。

---

## 5. 尚未验证（BLOCKED，需要 WorkBuddy 实机）

1. 自定义 stdio MCP 是否可接入（本机未安装 WorkBuddy）。
2. `env` token 是否透传；`_meta` 是否可用。
3. 工具超时、最大返回长度、并发限制。
4. 专家/Agent 分享链接能否被外部账号打开。
5. Workflow 是否有人工确认节点、能否回调。
6. ADP 路线作为兜底（队友已验证发布/分享链路，需组委会确认合规）。

---

## 6. 给队长的三句话

1. **契约数据语义保留**：`query_version/base_version` 分离、只回读 `planned_date/scheduled_at`、`readback_verified`。
2. **审批通道是硬缺口**：`request_approval` 只发 pending 请求，外部确认后 `get_approval_status` 才签一次性 token；否则 `apply` 永远 BLOCKED。
3. **身份按演示模式写**：`static_bearer_demo`，材料中披露；不在 v1 追 SSO。

---

## 附：交付物

- `tools/m1-mock/tool_server.py`：MCP stdio mock（5 v1 + 2 候选扩展），含契约校验、外部审批占位、一次性 token、幂等、回读、`readback_pending` 恢复。
- `tools/m1-mock/export_schema.py`：从 `tools/list` 导出候选 schema。
- `docs/contracts/tools.candidate.json`：候选 schema（含 `$defs`，未冻结）。
- `tools/m1-mock/run_evidence.py` → `docs/contracts/reviews/m1-evidence.md` / `.json`：26 条证据。
- `tools/m1-mock/mcp.json.example`：WorkBuddy 自定义连接器示例。
- `docs/contracts/reviews/workbuddy-test-plan.md`：实机 8 步验证清单（尚未执行）。