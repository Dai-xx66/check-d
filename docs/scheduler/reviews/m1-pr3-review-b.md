# B（M2）对 M1 PR #3 的只读评审

> 评审对象：`https://github.com/Dai-xx66/check-d/pull/3`
> 固定评审版本：`bbf0992307531f8945fe5ac25107e2da79dc0e76`（HEAD）
> 评审日期：2026-10-31　评审人：B（M2）
>
> **本轮只读**：未合并 PR、未修改任何业务代码、未执行任何 Git 写操作。
> 所有结论来自 `git show` / 源码阅读，**M1 的 mock 一行都没有在我本机运行过**。
> 因此凡涉及"运行结果"的陈述，一律标注为「静态结论」而非「实测结果」。
>
> 本文按队长要求落到 B 自己的评审分支留存，使评审意见可追踪。

## 0. 结论摘要

| 决议点 | 结论 |
|---|---|
| 工具数 5 → 7 | **同意**，但两个工具应进 v1 正文，不应停留在 candidate |
| 审批状态与 M2 Proposal 流程 | 语义兼容，**契约缺组合定义**，另有 3 处字段形状冲突必须先冻结 |
| 错误码 / 幂等 / 与 C 口径一致 | **三缺二**；幂等逻辑正确但摘要太弱；采纳 C 的 ALREADY_APPLIED 不可达结论 |
| 一次性 token + 外部确认后签发 | **规则同意**；实现有 3 个洞（绑定不全 / 二次轮询无码 / 有效期是装饰品） |
| Mock 18/18 的定位 | 仅证明 mock 内部自洽，**不代表** WorkBuddy 实机、真实审批服务或数据库写入 |

## 1. 是否同意增加到 7 个工具

同意。M2 是进程内纯函数，工具数不影响其输入输出契约。

语义上 `request_approval` 只建 pending、返回 url、**不签 token**；`get_approval_status`
仅在外部用户确认后签发一次性 token——这把「模型调用了工具」和「人确认了」切成两件事，
解决了契约 §7.1 自相矛盾导致 `apply` 永久 BLOCKED 的结构性问题。

**前提**：必须写进 v1 正文。停留在 candidate 会让 `APPROVAL_CONSUMED`、
`ALREADY_APPLIED` 与审批子状态机没有落脚点，C 无法冻结验收口径。

## 2. 审批状态与 M2 Proposal 流程的兼容性

语义兼容：审批是挂在 proposal 之外的**正交子状态机**
（pending / approved / expired / token_issued / consumed），不改动 §5.7 的 proposal 状态机。

**缺口 1：契约缺组合语义表。**
"proposal=pending_approval 且 approval=pending" 应判为何种状态，M3 无从判定。
建议契约补一张组合表。

**缺口 2：三处字段形状冲突**（只有 M2 侧能看到，冻结前必须一并定）：

| 字段 | M1 mock | M2 | 后果 |
|---|---|---|---|
| `explanations` | 字符串数组 | 对象数组 `{task_id, text}` | 合并时必有一方报 `PROPOSAL_INVALID` |
| `unplanned_tasks` | `{task_id, reason}` | `{task_id, remaining_minutes, reason_code, reason}` | A 无法做结构化差异展示 |
| `duration_source` | recurring 恒 `scheduler_estimate`，忽略目标时长 | 有 target 必须标 `task_target` | 标签与实际时长不符 |

## 3. 错误码、幂等与 C 的验收口径

**静态核对结果：**

| 码 | 现状 |
|---|---|
| `APPROVAL_REQUIRED` | 已在 §4.1，但**一码三义**（提案未校验通过 / 缺审批凭据 / 提案当前不可应用） |
| `APPROVAL_CONSUMED` | 不在 §4.1 |
| `ALREADY_APPLIED` | 不在 §4.1，**且判定路径不可达**（C 发现，我已复核属实） |
| `FIXED_EVENT_CONFLICT` 等 violation code | 契约完全未定义 |

**ALREADY_APPLIED 不可达的复核**：`tool_apply` 先判定 `status != pending_approval`
返回 `APPROVAL_REQUIRED`，之后才判 `pid in applied_proposals` 返回 `ALREADY_APPLIED`。
apply 执行后 `status` 变为 `applied`，于是**永远先撞上前置的状态检查**。
我上一轮曾写"applied_proposals 实现了换键也不能二次应用"，**此处更正我的说法，以 C 的为准**。

**幂等**：「最多成功应用一次」的意图正确，同键重放返回缓存、异请求冲突都对，
缓存判断在 consumed 判断之前（顺序正确）。唯一问题是 `req_digest` 只取 `token[:8]`，
不同 token 前缀相同即视为同一请求。同意 C 的改绑 `approval_id`。

## 4. 一次性 token 与外部确认后签发

规则赞成，实现有 3 个洞：

1. **token 绑定不全**：§7.1 要求绑 7 项，mock 只绑 `user / proposal_id / base_version`。
   缺 `change_digest` 最危险——token 没绑变更集，提案内容被换掉仍可能通过。
2. **二次轮询返回 `approval_token: null` 且无错误码**，token 丢失后无恢复路径，也无轮询上限。
3. **`expires_at` 是装饰品**：两处硬编码 `2026-10-30T23:59`（已过期）且无任何代码判过期，
   `APPROVAL_EXPIRED` 在这套实现里不可达，C 无法验收"审批过期"这条边界。

## 5. 冻结前必修（静态结论）

| # | 问题 | 依据行/位置 | 严重度 |
|---|---|---|---|
| 1 | `upsert_daily_override` 写完不回读，却返回 `readback_verified: true` | `tool_apply` 仅对 `schedule_one_time` 比对 | 红线 |
| 2 | `tools.candidate.json` 三个工具引用 `#/$defs/date_range`，但文件无 `$defs` 段 | schema 无法解析，`start`/`end` 实际零校验 | 红线 |
| 3 | 修好 2 之后，A16 的 `preferences.__test_conflict_event` 注入会失效 | `preferences` 为 `additionalProperties:false` | 高 |
| 4 | `deadline_key` 把 date_only 拼成 `T23:59:59+08:00` | 违反 §3.1 明文禁令 | 高 |
| 5 | recurring 忽略 `duration_target_seconds`，一律按 `minimum_block_minutes` 排 | 会静默少排且标签错误 | 高 |
| 6 | validate 从不重算 `input_digest` | `SNAPSHOT_CONFLICT` 不可达 | 高 |
| 7 | `STATE["tasks"][ch["task_id"]]` 直接下标取值 | 缺失时抛 `KeyError` 未被 `ToolError` 捕获，会崩而非返回 `NOT_FOUND` | 高 |
| 8 | error code / violation code 未入 §4.1 | C 无判定依据 | 高 |
| 9 | apply 逐条写、无回滚，证据措辞却是"原子应用" | 需补事务或 `WRITE_BLOCKED` 路径 | 中 |

## 6. 必须保持 BLOCKED

1. WorkBuddy 实机（stdio 自定义 MCP、env/headers 与 `_meta` 透传、超时与返回长度上限、分享链接能否被外部账号打开）。
2. 真实审批服务与确认页（当前是往 JSON 文件写状态：**无登录主体校验、无签名、无防重放**）。
3. 真实数据库写入：Drift/Supabase 原子性、RLS、SyncQueue 收敛、`readback_pending` 恢复。
4. `base_version` 跨表原子快照：mock 的 digest 是单机内存计算，不是可信版本服务。
5. 身份模型（`static_bearer_demo` 还是终端用户 SSO）需队长拍板。
6. 幂等存储、并发锁、崩溃恢复。
7. 数值：31 天上限、提案有效期、幂等保留期、`FORBIDDEN`/`NOT_FOUND` 策略。

**边界声明**：18/18 只能证明 mock 内部自洽，
**不能**证明 WorkBuddy 实机、真实审批服务或真实数据库写入已通过。
M1 自己的这条声明写得很诚实，建议原样保留进比赛材料。
