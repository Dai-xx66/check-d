# M0 Agent API v1 验收矩阵（T01–T22）

- **归属**：M3 / Evaluation（同学 C）
- **固定基准**：`2c48579a6f0ab2b9181a9246f893c1c0a8dce7c6`（分支 `feat/m0-api-contract`，PR **M0-1 / #4** 的 head，`docs/contracts/agent-api-v1.md`，v1 CANDIDATE 最终决策稿）
- **基准唯一性**：C 侧全部用例与判定只认上述 SHA；M0 再发新 commit 时按 §9 重跑一次，不混用旧版本结论
- **状态**：**预期定义阶段，尚未执行任何一条**
- **纪律**：本文件只写"输入"与"预期"。所有预期列都是**待验证的断言**，不是实测结果。执行后再另开一节回填实测值，本文件在此之前不得被引用为"已通过"。
- **复核时点**：`2c48579` 已完成一次增量复审（`docs/reviews/2026-10-31-m0-final-2c48579-incremental-M3.md`）；M0 将其作为 Task 1 固定基准发布（PR M0-1）后，按 C 口径完成**增量对齐**（`docs/reviews/2026-10-31-c-incremental-alignment-2c48579.md`），未重开全量审计、未重跑实测。

判定口径统一为四元组：**响应码 + Proposal 状态 + 数据结果 + 实际写入次数**。四项全部吻合才算 PASS。

---

## 1. 公共前置（所有用例共用）

固定业务时区 `Asia/Shanghai`，固定逻辑日期 `2026-11-01 ~ 2026-11-07`，全部 ID 为虚构值。

| 别名 | 对象 | 关键属性 | 供哪些用例使用 |
|---|---|---|---|
| `T_RE_1` | 周期任务 | `daily`，无 `duration_target_seconds` | T04、T07、T09 |
| `T_RE_2` | 周期任务 | `weekdays`，`duration_target_seconds=3600` | T12 |
| `T_OT_1` | 单次事项 | `planned_date=2026-11-02`，无 `scheduled_at`，`available_from=2026-11-01`，`deadline={kind:date_only,date:2026-11-05}` | T01–T03、T10 |
| `T_OT_2` | 单次事项 | `planned_date=2026-11-03`，`scheduled_at=2026-11-03T09:00:00+08:00` | T11 |
| `C_1` | 课程 | 周一第 3–4 节（`start_minute=600`，`end_minute=720`），`fixed=true` | T04（对照不变量） |
| `OV_1` | 已存在的单日例外 | `item_type=recurring`、`item_id=T_RE_1`、`local_date=2026-11-03`、`action=reschedule`、`600–660` | T09 |

每个用例开始前的 Proposal 统一处于 `pending_approval`，`approval_token` 有效，`idempotency_key` 未使用过（除显式复用外）。

---

## 2. 状态机与用例映射（先看这张表）

> 目的：让"某个错误码在什么状态下可达"可被直接检查。标 `[未定义]` 的是契约 §5.7 当前没有的状态值——这正是 B1 的根因。

### 2.1 Proposal（8 个状态值，`2c48579` 已全部定义）

| 迁移 | 触发 | 对应用例 | 契约定义情况 |
|---|---|---|---|
| `draft` → `pending_approval` | validate 通过 | T01 前置 | 已定义（§5.7 状态机图、§6.4） |
| `draft` 保持 `draft` | 硬约束违反 | T10、T11 | 已定义（§6.4 `validation_status=invalid`） |
| `pending_approval` → `applying` → `applied` | apply 成功且回读一致 | T02、T12 | 已定义（§5.7、§6.7） |
| `pending_approval` → `applying` → `readback_pending` | 写入可能已提交、回读未决 | T01 | 已定义（§5.7 + §6.7 + 示例 19） |
| `applied` → `applied` | 换幂等键再次 apply | T08 | 已定义（§6.7 第 2 步 → `ALREADY_APPLIED`） |
| `pending_approval` → `expired` | 超过 30 分钟 TTL | T06 | 已定义（§5.7 状态机 + §6.7） |
| `pending_approval` → `rejected` | 用户在外部界面拒绝 | T16 | 已定义（§6.6 `status=rejected`） |
| `applying` → `failed` | "safe failure"（写入确证未发生） | T03-a | **部分**：有箭头但"safe"未定义、无对应错误码、且与 `READBACK_MISMATCH` 后终态未区分（B14、B16） |

### 2.2 Approval（6 个状态值）

| 迁移 | 触发 | 对应用例 | 契约定义情况 |
|---|---|---|---|
| 创建 → `pending` | `request_approval` | T16 | 已定义（§6.5） |
| `pending` → `approved` | 外部确认通过 | T16 | 已定义（§6.6） |
| `approved` → `token_issued` | 首次安全交付 Token | T19、T21 | 已定义（§6.6）；**并发交付原子性未写**（P2-2） |
| `token_issued` → `consumed` | apply 成功消费 | T18 | 状态已定义，但对应错误码不可达（P1-1） |
| `pending` → `expired` | 审批或 Token 过期 | T05 | 已定义（§6.6，区分"仅 Token 过期"与"Proposal 也过期"） |
| `expired` → 新审批 | 再次 `request_approval` | T17 | **部分**：允许重建，但未定返回新/旧 `approval_id` |
| 任意 → `rejected` | 用户拒绝 | T16 | 已定义（§6.6） |

> **注意同名双域**：本节 6 个状态仅指 `get_approval_status.data.status`。`validate_schedule.data.approval_status` 是**另一套**枚举（`not_requested` / `not_approvable`，§6.4），两者零交集，见 B17。

### 2.3 错误码 × 可达性（§4.1 共 20 个）

> 判定口径 G1：**只认"能触发"，不认"文档里有"**。`2c48579` 的 20 个示例中只有 8 个是错误响应。

| 错误码 | 触发条件 | 示例 | 对应用例 | 判定 |
|---|---|---|---|---|
| `AUTH_REQUIRED` | 凭证缺失/无效 | 4 | — | 可判 |
| `FORBIDDEN` | §8 未定策略 | 无 | T09-b | **不可判（B7）** |
| `INVALID_ARGUMENT` | 请求体带 `user_id`、字段非法 | 无 | T13 | 可判 |
| `NOT_FOUND` | §8 未定策略 | 无 | T09-b | **不可判（B7）** |
| `DEPENDENCY_UNAVAILABLE` | 依赖不可用 | 无 | — | 部分 |
| `PROPOSAL_INVALID` | 结构/change 类型非法；`scheduled_at` 跨日 | 无 | T11、T15 | 可判 |
| `PROPOSAL_EXPIRED` | Proposal 超 30 分钟 | 15 | T06 | 可判 |
| `SNAPSHOT_CONFLICT` | 版本/摘要不符；override 唯一键撞库 | 18 | T04、T04-b、T09-a | 可判 |
| `APPROVAL_REQUIRED` | 无审批记录 | 无 | T05 前置 | 可判 |
| `APPROVAL_PENDING` | 有审批但仍 pending | 11 | T07 | 可判 |
| `APPROVAL_REJECTED` | 用户拒绝 | 无 | T16 | 可判 |
| `APPROVAL_EXPIRED` | Token 过期 | 17 | T05 | 可判 |
| `APPROVAL_UNTRUSTED` | **正文零触发条件** | 无 | T22 | **不可判（P1-2）** |
| `APPROVAL_CONSUMED` | **判定顺序使其不可达** | 16（与正文冲突） | T18 | **不可判（P1-1）** |
| `ALREADY_APPLIED` | Proposal 已 applied | 14 | T08 | 可判 |
| `IDEMPOTENCY_CONFLICT` | 同键异摘要/异提案 | 无 | T07 | 可判 |
| `WRITE_BLOCKED` | 无法证明原子性 | 无 | — | 可判（依赖 BLOCKED 项） |
| `READBACK_PENDING` | 写入可能已提交、回读未决 | 19 | T01、T02、T03-b | 可判 |
| `READBACK_MISMATCH` | 写后回读不一致 | **无示例** | T03-a | 可判（终态另行待定，B16） |
| `INTERNAL_ERROR` | 脱敏未知错误 | 无 | — | 部分 |

---

## 3. 主矩阵

### T01 写后回读不可见 → 进入 readback_pending

- **输入**：apply `{proposal_id, base_version, approval_token, idempotency_key=K1}`；故障注入：写入链路成功提交，但回读路径返回空（模拟 RLS 生效延迟）
- **预期响应码**：`READBACK_MISMATCH`（502）
- **预期 Proposal 状态**：**`[待定]`** —— 契约 §5.7 无此状态；按 P0-1 建议应为 `readback_pending`
- **预期数据结果**：库中已有 1 条变更（可能已提交），但响应**不得**声称成功、不得回填 `applied_changes`
- **预期写入次数**：**1**（第一次写入发生且只发生一次）
- **判定要点**：`READBACK_MISMATCH` 与「写入真的失败了」不可混淆；见 §5 阻塞项 B1

### T02 同键重试，回读恢复

- **输入**：T01 之后，用**同一** `idempotency_key=K1` 再次 apply（回读此时可见）
- **预期响应码**：`success`
- **预期 Proposal 状态**：`applied`
- **预期数据结果**：`readback_verified=true`；`applied_changes` 与 T01 实际落库内容一致；无新增行
- **预期写入次数**：**累计仍为 1**（重试只做回读，不得二次写入）
- **判定要点**：这是幂等能力的核心断言。写入次数若变 2，本用例直接 FAIL

### T03-a 写后回读不一致 → `READBACK_MISMATCH`（新增拆分）

- **输入**：`T_RE_1` 的 `reschedule` 提案已批准并 apply；注入"写入成功但回读值不同"（回读返回 `planned_start_minute` 比批准值多 5）
- **预期响应码**：`READBACK_MISMATCH`（502），**不得返回 `success`**（§4.1 + §6.7「任何缺失或不一致返回 `READBACK_MISMATCH`，不得返回成功」）
- **预期 Proposal 状态**：**`[待定]`** —— 契约只规定"不得返回成功"，未规定此后状态（停留 `applying` / `failed` / `readback_pending` 三选一），见 **B16**
- **预期数据结果**：已写入数据**不得自动回滚**（契约未授权回滚）；须留可审计记录（`override_id`、批准值、回读值）；`readback_verified` 不得为 `true`
- **预期写入次数**：**1**（写入已发生，不因回读失败消失；重试不得产生第 2 次写入）
- **判定要点**：`e7be8c9` 实测的 F3 是此条反例——回读失败仍 `readback_verified=true` 且 `proposal_status=applied`。断言必须同时查"响应码 + `readback_verified` + 库中实际值"，只看响应码会被假成功骗过

### T03-b 回读无法完成（不确定）→ `READBACK_PENDING`，同键只回读

- **输入**：apply 已完成写入，但回读通道故障（超时 / 依赖不可用），无法给出"一致"或"不一致"的结论
- **预期响应码**：`READBACK_PENDING`（503）
- **预期 Proposal 状态**：`readback_pending`
- **预期数据结果**：幂等记录被标为 `readback_pending`；**同一幂等键重试只能重新回读/核验，不得再次写入**；通道恢复且回读一致后，返回原 apply 结果（`applied_changes`、`result_version`、`readback_verified=true`），Proposal 转 `applied`
- **预期写入次数**：**恒为 1**（同键重试 N 次仍为 1）
- **判定要点**：这是"只能安全回读、不得重写"唯一可执行的断言，须用目标表行数 + `override_id` 双重确认。§10 Q5 把「`readback_pending` 的恢复流程」列为 open，但 §6.7「同键只回读」已是确定语义——本条**可判**，恢复上限与超时值不影响本条判定

### T04 apply 阶段版本冲突

- **输入**：validate 通过后，另一设备修改 `T_RE_1`（改变 `updated_at` 与快照内容），随后 apply 原 `base_version`
- **预期响应码**：`SNAPSHOT_CONFLICT`（409）—— 需 M0 在 §6.5 显式绑定，当前仅写在 validate 段（P0-2）
- **预期 Proposal 状态**：保持 `pending_approval`，该 `approval_token` 失效
- **预期数据结果**：零变更；`C_1`、`OV_1`、其他 Task 均不变
- **预期写入次数**：**0**
- **判定要点**：失败后不得让客户端用旧 token 反复重试；**前置条件是 validate 真的重算了 `input_digest`**——若摘要未重算，本用例会假通过（构造的是"字段不符"而非"快照漂移"）

### T04-b validate 阶段摘要不符（A3 配套，新增）

- **输入**：两次读取之间修改 `T_RE_1` 的 `updated_at`，再用旧 `base_version` + 旧 `input_digest` 调用 validate
- **预期响应码**：`SNAPSHOT_CONFLICT`（409）
- **预期 Proposal 状态**：`draft`（不得进入 `validated`）
- **预期数据结果**：不生成 token；零写入
- **预期写入次数**：**0**
- **判定要点**：用于区分"摘要重算触发"与"硬编码返回"——若只有传错字段才报冲突、真实漂移不报，判 G1 假修复

### T05 审批凭据过期

- **输入**：`approval_token` 超过其 `expires_at` 后 apply
- **预期响应码**：`APPROVAL_EXPIRED`（403）
- **预期 Proposal 状态**：`pending_approval`（不得 `applied`）
- **预期数据结果**：零变更
- **预期写入次数**：**0**
- **判定要点**：与 T06 必须可区分

### T06 提案过期

- **输入**：`proposal.expires_at` 已过，审批 token 仍在有效期内，执行 apply
- **预期响应码**：**`[待定]`** —— 契约无对应码；建议 `PROPOSAL_EXPIRED`（410）
- **预期 Proposal 状态**：`expired`
- **预期数据结果**：零变更
- **预期写入次数**：**0**
- **判定要点**：若 M0 决定复用 `APPROVAL_EXPIRED`，则 T05/T06 无法区分，验收需降级为"仅看 Proposal 状态"

### T07 并发 apply（同一幂等键）

- **输入**：两个请求**同时**携带 `K1` 提交
- **预期响应码**：一个 `success`；另一个 **`[待定]`** —— 契约只说"共享同一执行结果"，未定义执行中的响应（建议 `409` + `idempotency_state=in_progress`，或 `202`）
- **预期 Proposal 状态**：`applied`（只一次）
- **预期数据结果**：1 条变更，内容与单请求一致
- **预期写入次数**：**1**
- **判定要点**：并发窗口需可控（建议在 Mock 服务端注入 300ms 写延迟），否则本用例不可复现

### T08 重复 apply（不同幂等键，同一 Proposal）

- **输入**：`K1` 成功完成后，用 `K2` 对同一 Proposal 再次 apply
- **预期响应码**：**`[待定]`** —— 建议 `PROPOSAL_ALREADY_APPLIED`（409）；契约只有"最多应用一次"的约束，无错误码
- **预期 Proposal 状态**：`applied`（保持不变）
- **预期数据结果**：无新增、无修改；响应可携带首次 `result_version` 供对账
- **预期写入次数**：**累计仍为 1**
- **判定要点**：检查顺序必须是"先判 Proposal 已应用，再判幂等键"，否则会误报 `IDEMPOTENCY_CONFLICT`

### T09 override 唯一键冲突

拆三个子场景，共用 `OV_1`（`T_RE_1` / `2026-11-03`）。

| 子例 | 输入 | 预期响应码 | 预期状态 | 预期数据 | 预期写入次数 |
|---|---|---|---|---|---|
| T09-a | `upsert_daily_override` 不带 `existing_override_id`，目标日期已有 `OV_1` | `[待定]`：建议 `PROPOSAL_INVALID` 或 `INVALID_ARGUMENT` | `draft` | 不新增行 | **0** |
| T09-b | 带一个属于其他用户 / 其他 item 的 `existing_override_id` | `FORBIDDEN` 或 `NOT_FOUND`（策略待定） | `draft` | 不新增、不修改他人数据 | **0** |
| T09-c | 带正确的 `OV_1` ID | `success` | `applied` | 该行被更新，`local_date=2026-11-03` 上**仍只有 1 行** | **1（更新）** |

- **回读字段断言（F7 补充）**：三个子例的"更新"都必须校验**完整字段**——`action`、`item_type`、`item_id`、`local_date`、`planned_start_minute`、`planned_end_minute`、`override_id` 七项全部一致。`e7be8c9` 只校验起止分钟，若实现把 `reschedule` 写成 `skip` 而分钟相同，回读仍会 PASS。
- **判定要点**：真实库对 `(userId, itemType, itemId, localDate)` 建了唯一键（`app_database.dart:366-368`），而写入实现在无 `overrideId` 时生成新 uuid（`day_schedule_repository.dart:57-80`）——**不校验 `existing_override_id` 就必然撞唯一约束**。T09-a 就是把这个撞库点变成契约行为。行数断言必须直接查表，不能只看接口返回。

### T10 available_from / deadline 冲突

两个子场景，目标是 `T_OT_1`。

| 子例 | 输入 | 预期响应码 | 预期状态 | 预期 `violations` | 预期写入次数 |
|---|---|---|---|---|---|
| T10-a | `planned_date=2026-10-30`（早于 `available_from=2026-11-01`） | `success` + `validation_status=invalid` | `draft` | `[待定]`：建议 `planned_before_available_from` | **0** |
| T10-b | `planned_date=2026-11-06`（晚于 `deadline=2026-11-05`） | `success` + `validation_status=invalid` | `draft` | `[待定]`：建议 `planned_after_deadline` | **0** |

- **判定要点**：这两条是**硬约束违反**，按 §6.4 应返回成功响应 + `invalid`，不是 `PROPOSAL_INVALID`（422）。真实代码在 `task_models.dart:183-200` 直接抛 `ArgumentError`，服务端若不前置校验，错误会以 500 或静默失败出现。
- **依赖**：`violations[].code` 的枚举当前未定义（P1-8），故本用例的字段级断言暂不可判。

### T11 已有 scheduled_at 时只改 planned_date

- **输入**：`schedule_one_time` 目标 `T_OT_2`（已有 `scheduled_at=2026-11-03T09:00+08:00`），change 只给 `planned_date=2026-11-04`，不带 `scheduled_at`
- **预期响应码**：`success` + `validation_status=invalid`（或 apply 阶段返回 `PROPOSAL_INVALID`，取决于 M0 是否把该冲突归为结构性错误）
- **预期 Proposal 状态**：`draft`
- **预期数据结果**：零变更；**特别断言**：不得出现"planned_date 已改为 11-04，但回读 `effective_planned_date` 仍是 11-03"的状态
- **预期写入次数**：**0**
- **判定要点**：`effectivePlannedDate` 优先取 `scheduledAt`（`task_models.dart:69-73`），同日校验在 `:176-179`。契约需明确 `clear_scheduled_at` 或"此时 `scheduled_at` 变必填"，否则这条 change 在真实代码上**必然失败**，且失败形态是合法的 `READBACK_MISMATCH`，排障成本极高。

### T12 end_at 不参与持久化验收

- **输入**：`schedule_one_time` 安排 `T_RE_2`（有 `duration_target_seconds=3600`）到 `2026-11-04T14:00:00+08:00`，block `end_at=15:30`（故意比目标时长多 30 分钟），`duration_source=scheduler_estimate`
- **预期响应码**：`success`
- **预期 Proposal 状态**：`applied`
- **预期数据结果**：`planned_date=2026-11-04`、`scheduled_at=14:00` 均正确；`readback_verified=true`；库中不存在结束时间列，**不得因 `end_at` 与任何列不符而判失败**
- **预期写入次数**：**1**
- **反向断言**：把 block 的 `end_at` 改成任意合法值（如 16:00），只要 `start_at` 不变，回读结果必须仍然 PASS。若反向断言 FAIL，说明实现错误地把 `end_at` 纳入了回读断言
- **判定要点**：这是保护 §5.6 设计的守卫用例，防止实现"顺手"把估算时长写成持久化字段

### T12-b 周期任务时长来源优先级（A5 配套，新增）

- **输入**：对重复任务 `T_RE_1` 发起排程，分别构造三种情况：(a) 任务自带 `duration_target_seconds=1800` 且快照估算 `2700`；(b) 任务无自带值、快照估算 `2700`；(c) 两者皆无
- **预期响应码**：三种情况均 `success`
- **预期 Proposal 状态**：`applied`
- **预期数据结果**：`duration_source` 依次为 `task_target` / `scheduler_estimate` / `scheduler_estimate`（后两档同为估算，区别在取值来源：快照估算 vs `max(preferences.minimum_block_minutes, 30)`）
- **预期 `duration_seconds`**：(a) 1800；(b) 2700；(c) `max(minimum_block_minutes, 30) × 60`；block 的 `end_at` 随之变化，但**库中仍无结束时间列**，回读只校验 `planned_date` + `scheduled_at`
- **预期写入次数**：各 **1**
- **判定要点**：优先级必须是 `duration_target_seconds`（周期任务用折算后的 `remaining_minutes_today`，null→完整目标、0→不生成 block）> 快照估算 > 兜底。**枚举只有 `task_target` 与 `scheduler_estimate` 两个值**（`2c48579` 已统一，旧实现/旧契约里的 `snapshot_estimate`、`fallback` 用词已废弃）。`duration_source` 若恒为同一值说明未真正分档；若出现第三值说明枚举未对齐。本用例不得被误读为"`end_at` 要写入数据库"——T12 的反向断言仍然生效

### T15 `skip` 不在 v1 白名单（负向用例，`2c48579` 已定稿）

> 上一轮此用例是「分支 A/B 待 M0 二选一」的条件式占位。`2c48579` §5.7 已定：**`skip` 不属于 v1 change 白名单**，排不下的任务只能留在 `unplanned_tasks` 中作为非持久化建议。因此改为负向用例，不再有分支。

- **输入**：三路分别构造 ——（a）Proposal 的 `changes` 含 `type: "skip"`；（b）对 `T_RE_1` 表达"跳过 2026-11-04"并要求生成提案；（c）`T_RE_1` 当天可用窗口小于 `max(minimum_block_minutes, 30)`
- **预期响应码**：（a）`PROPOSAL_INVALID`；（b）`success`，该任务只能出现在 `unplanned_tasks` 或完全不出现，**不得产生任何 change**；（c）`success` + `unplanned_tasks[].reason_code=WINDOW_INSUFFICIENT`
- **预期 Proposal 状态**：（a）不创建 Proposal，或创建后保持 `draft`；（b）（c）`pending_approval`（若已 validate）或 `draft`
- **预期数据结果**：三路均**不得**写入 `action=skip` 的单日例外；`daily_override` 表行数不变；任务 `status` 不变；`TimerSession`、完成记录、周期规则均不变
- **预期写入次数**：**0**（三路全部）
- **判定要点**：真实代码存在 `action=skip` 例外类型（`today_page.dart` 范例），实现极易"顺手"把 skip 落库。**只要出现一条 `action=skip` 记录即判失败**，无论响应码是否 success。这是防止 v1 越过已决策边界的守卫用例
- **附注**：`reason_code` 枚举固定为 `WINDOW_INSUFFICIENT` / `PAST_DEADLINE` / `OVERLAPS_FIXED` / `NO_AVAILABILITY`。旧 Mock 用的 `no_free_slot`、`insufficient_window` 已废弃，新实现必须改，否则旧用例会假通过

### T16 审批第三态与重复 request 幂等（A8 配套，新增）

- **输入**：对同一 Proposal `P_1` 连续调用三次 `get_approval_status`，并在第一次与第二次之间重复调用一次 `request_approval`
- **预期响应码**：三次轮询均 `success`；重复 `request_approval` 返回 `success` 且不新建记录
- **预期 Proposal 状态**：全程 `pending_approval`，不因轮询推进
- **预期数据结果**：
  - 状态序列必须是 `pending` →（外部确认）→ `token_issued` →（apply 后）→ `consumed`；**token 签发后轮询返回 `token_issued`，不得返回 `approved` + `token: null`**
  - 重复 `request_approval` 返回**同一 `approval_id`**，审批记录条数恒为 1
  - `consumed` 之后再次轮询不得重新签发 token
- **预期写入次数**：审批记录 **1 条**（重复 request 不新增）；Proposal 表 **0 次变更**
- **判定要点**：旧实现把"已批准未签发"和"已签发"混成一个 `approved`，客户端无法判断能否 apply。第三态缺失属 F1（契约缺陷），状态枚举不在契约中则本条不可判（B8 相关）

### T17 审批过期后重新发起（新增，e7be8c9 实测发现）

- **输入**：`P_1` 已创建审批 `A_1`，等到 `A_1.expires_at` 之后（或注入时钟），再次对 `P_1` 调用 `request_approval`
- **预期响应码**：`success`，且返回**新的** `approval_id`（`≠ A_1`）、`status=pending`、`expires_at` 在未来
- **预期 Proposal 状态**：`pending_approval`（不变）
- **预期数据结果**：旧审批标记 `expired`（落库，不只是计算）；新审批可再次走确认 → 签发 → apply
- **预期写入次数**：审批表 **+1 条**
- **判定要点**：`e7be8c9` 实测**不通过**——`request_approval` 复用条件写的是 `rec["status"] != "expired"`（`tool_server.py:561`），但代码从不把 `status` 写成 `expired`（`:590` 仅即时计算），导致过期审批被永久复用，提案**再也无法获得可用凭据**，形成锁死。属 F2 实现缺陷
- **可判性说明**：「返回**新** `approval_id`」是**推断**而非明文——§6.5 的幂等返回同一 ID 仅限"已有**未终结**审批"，过期属已终结，故应新建。建议 M0 在 §6.6 补一句"审批过期后重建必须产生新 `approval_id`，旧 ID 永久不可用"，本条即从推断转为明文判定

### T18 token 已消费（APPROVAL_CONSUMED 可达性，新增）

- **输入**：`P_1` 正常 apply 成功后，分别执行三件事：① 用同一 token 再 apply（换幂等键）；② 轮询该审批；③ 对 `P_1` 再次 `request_approval`
- **预期响应码**：① `ALREADY_APPLIED`（409）；② `success` 且 `status=consumed`；③ `PROPOSAL_NOT_APPROVABLE`
- **预期 Proposal 状态**：`applied`，不因上述调用改变
- **预期数据结果**：审批记录进入 `consumed`，`consumed_at` 有值；不得再签发新 token；不得新建审批
- **预期写入次数**：三件事合计 **0**
- **判定要点**：`APPROVAL_CONSUMED` 当前**双方都没有**——契约 §4.1 无该码，实现已按 A 的说明删除（重复 apply 统一走 `ALREADY_APPLIED`）。本用例的价值在于把「consumed 是可观察状态」与「consumed 不是独立错误码」两件事分开：状态必须有，错误码可以复用。若 M0 决定不恢复该错误码，② 的 `status=consumed` 仍需成立，否则审计无法区分"已用"与"未用"

---

### T19 Token 5 分钟 TTL、一次性与不越过 Proposal 到期（新增）

- **输入**：Proposal `P_1` 于 `T0` 生成（TTL 30 分钟）；`T0+2min` 用户外部批准并首次交付 Token。分别在（a）`T0+6min` 用该 Token apply；（b）`T0+3min` 用该 Token apply 成功；（c）成功后**换幂等键**重试；（d）成功后**同幂等键**重放
- **预期响应码**：（a）`APPROVAL_EXPIRED`（403）；（b）`success`；（c）`ALREADY_APPLIED`；（d）`success` 且返回与（b）完全相同的结果
- **预期 Proposal 状态**：（a）仍 `pending_approval`（**仅 Token 过期，提案未过期**）；（b）（c）（d）`applied`
- **预期数据结果**：`token_expires_at - token_issued_at ≤ 300s` 且 `token_expires_at ≤ proposal.expires_at`；`get_approval_status` 在（a）返回 `status=expired`；过期后再次 `request_approval` **必须给出可用新凭据**（见 T17）
- **预期写入次数**：**1**（仅（b））；a/c/d 均为 0 次新增写入
- **判定要点**：Token TTL 是"签发后 5 分钟"，不是"审批创建后 5 分钟"，也不是"当天 23:59 封顶"——`e7be8c9` 的实现完全没有 token 过期字段，这一条在旧实现上必然失败。同时验证"仅 Token 过期不连带提案过期"这一分支

### T20 `scheduled_at` 的省略 / null / 跨日三态（新增，F6 回归）

- **输入**：`T_OT_2` 当前 `planned_date=2026-11-03`、`scheduled_at=2026-11-03T09:00:00+08:00`。四种 change：（a）`planned_date=2026-11-05`，**省略** `scheduled_at`；（b）`planned_date=2026-11-03`，`scheduled_at=null`；（c）`planned_date=2026-11-05`，`scheduled_at=2026-11-05T09:30:00+08:00`；（d）`planned_date=2026-11-05`，`scheduled_at=2026-11-03T09:00:00+08:00`
- **预期响应码**：（a）`PROPOSAL_INVALID`——省略表示保留现值 `11-03T09:00`，与新的 `planned_date=11-05` 不同日，必须拒绝；（b）`success`；（c）`success`；（d）`PROPOSAL_INVALID`（跨日）
- **预期 Proposal 状态**：（b）（c）`applied`；（a）（d）不进入 `applying`
- **预期数据结果**：（b）库中 `scheduled_at` 变为 `NULL`，`planned_date` 仍 `11-03`；（c）库中 `scheduled_at=11-05T09:30`、`planned_date=11-05`；（a）（d）库**零变更**，且不得出现"响应 success 但库中 `scheduled_at` 被清空"
- **预期写入次数**：（b）（c）各 1；（a）（d）**0**
- **判定要点**：**省略 ≠ null**。JSON 层必须区分"字段缺失"与"显式 null"，实现若用 `ch.get("scheduled_at")` 取值就会把省略当 null——这正是 `e7be8c9` 实测的 F6（静默清空旧值且 `readback_verified=true`）。断言必须**直接查库字段值**，不能只看响应与 `readback_verified`

### T21 `approved → token_issued` 的并发交付原子性（新增）

- **输入**：审批已 `approved`、Token 尚未交付。并发发起两次 `get_approval_status`（同一 `approval_id`）
- **预期响应码**：两次均 `success`
- **预期 Proposal 状态**：`pending_approval` 不变
- **预期数据结果**：**恰好一次**返回 `approval_token` 非 null + `token_issued_at` + `token_expires_at`；另一次必须返回 `status=token_issued` + `approval_token=null`。两次响应不得都携带 Token
- **预期写入次数**：Token 签发 **1** 次（以 `approval_token` 记录数为准）
- **判定要点**：契约只写了"仅首次安全交付时返回"，**未声明该迁移原子**（P2-2）。本用例当前判为**部分可判**；契约补一句"`approved → token_issued` 为原子迁移，并发轮询中仅一个响应可携带 Token"即可完全可判

### T22 凭证绑定篡改 → `APPROVAL_UNTRUSTED`（新增）

- **输入**：持有 `P_1` 的有效 Token，构造三种篡改：（a）换 `proposal_id` 为另一有效提案 `P_2`；（b）Token 不变但 `base_version` 改为 `P_1` 的旧版本；（c）重复提交时改 `changes` 摘要（请求体不得携带 changes，故改为用 `P_2` 的 Token 打 `P_1`）
- **预期响应码**：三路均应为 `APPROVAL_UNTRUSTED`（403）
- **预期 Proposal 状态**：`P_1`、`P_2` 均保持原状态，不回退、不进 `applying`
- **预期数据结果**：零变更；Token 不被标记消费（除（c）语义外）
- **预期写入次数**：**0**（三路）
- **判定要点**：`APPROVAL_UNTRUSTED` 在 `2c48579` 全文（除 §4.1 表格）**零次出现**，§6.7 要求核验"凭证绑定完全相同的 `proposal_id`、`base_version` 和变更摘要"却没有给这条核验分配错误码（P1-2）。当前**不可判**：同一个"他提案 + 旧 Token"场景，示例 16 判给 `APPROVAL_CONSUMED`，按 §6.7 第 2 条应判 `APPROVAL_UNTRUSTED`，两者互斥

## 4. 覆盖对照（按 `2c48579` 重新判定）

| 重点 | 覆盖用例 | 当前可判性（`2c48579`） |
|---|---|---|
| `readback_pending` | T01、T02、T03-b | **均可判**（状态值 + `READBACK_PENDING` 错误码 + 同键只回读、写入次数恒为 1） |
| 回读失败（不一致） | T03-a | **部分可判**——响应码/写入次数可判，Proposal 终态 `[待定]`（B16） |
| 版本冲突 | T04、T04-b | **可判**（§6.7"以上均为零写入" + §6.4 摘要重算） |
| 并发 apply | T07 | 部分可判——执行中响应仍未定义（B6） |
| 重复 apply | T08 | **可判**（判定顺序第 2 步 → `ALREADY_APPLIED`） |
| override 唯一键冲突 | T09-a/b/c | T09-a **可判**（§5.7 明确 `SNAPSHOT_CONFLICT` 零写入、不得换 id 重复建）；T09-b 不可判（B7）；T09-c **可判**（回读 7 字段已写死） |
| available_from / deadline | T10-a/b、T11 | T11 **可判**（跨日 → `PROPOSAL_INVALID`）；T10 部分（`violations[]` 项结构未定，B5） |
| `end_at` 不参与持久化验收 | T12、T12-b | **均可判**（§5.6 表述清晰；`duration_source` 枚举已统一为 2 值） |
| `skip` 不持久化 | T15 | **可判（负向）**——§5.7 已定 `skip` 不在白名单，只要落库即失败 |
| Token 5 分钟 / 一次性 | T19 | **可判**（§6.6 + §7.1 写明 TTL 与不越过 Proposal 到期） |
| `scheduled_at` 三态 | T20 | **可判**（§5.7 明确省略=保留、null=清除、跨日 `PROPOSAL_INVALID`） |
| 并发 Token 交付 | T21 | 部分可判——原子性未声明（P2-2） |
| 凭证绑定篡改 | T22 | **不可判**——`APPROVAL_UNTRUSTED` 无触发条件（P1-2） |
| `APPROVAL_CONSUMED` | T18 | **不可判**——判定顺序使其不可达（P1-1） |
| A 侧 10-31 修订（9 项待处理） | T04-b、T08、T12-b、T05/T06、T09-b、T16、T10 | 判据见 `docs/reviews/2026-10-31-a-fix-verification-checklist-M3.md`；A 需按新契约重跑 |

附两条低成本用例：T13 请求体带 `user_id` → `INVALID_ARGUMENT`；T14 空任务/空日历 → `success` + 空数组（不得 404）。

**统计（22 个编号 / 23 个用例项，T03 已拆 a/b）**：完全可判 **16**、部分可判 **4**（T03-a、T07、T10、T21）、不可判 **3**（T09-b、T18、T22）。相比 `2c48579` 首轮复审（15/3/4），本轮把回读失败拆开后新增 1 条可判项（T03-b），T03-a 由"完全不可判"降级为"部分可判"。

### 4.1 队长 10-31 指定保留的 8 项 → 用例索引

| 指定项 | 用例 | 状态机位置 | 当前可判性（`2c48579`） |
|---|---|---|---|
| Proposal / Approval 状态机 | §2.1、§2.2 全表；T16、T18 | — | 8 个 Proposal 状态、6 个 Approval 状态**已全部定义**；仅 2 处迁移条件待补（`failed`、过期后重建） |
| `readback_pending` | T01、T02、T03-b | §2.1 第 4 行 | **可判**；回读不一致另见 T03-a（终态待 B16） |
| `PROPOSAL_EXPIRED` | T06 | §2.1 第 6 行 | **可判**（状态值 + 错误码 + 示例 15） |
| `APPROVAL_EXPIRED` | T05、T17、T19 | §2.2 第 5 行 | **可判**（§6.6 区分仅 Token 过期 / 提案也过期） |
| `ALREADY_APPLIED` | T08 | §2.1 第 5 行 | **可判**（判定顺序第 2 步） |
| `APPROVAL_CONSUMED` | T18 | §2.2 第 4 行 | **不可判**（P1-1，第三次"码在路不通"） |
| daily override 回读 | T09-a/b/c（七字段断言） | — | T09-a/T09-c 可判；T09-b 待 B7 |
| item 不存在 | T09-b | — | 待 B7（`FORBIDDEN` vs `NOT_FOUND`） |
| 四项判定（码/状态/数据/写入次数） | 全部用例 | — | 保持，§6 已固化取证规则；**注意 apply 成功响应无 `proposal_status`（P2-1），"状态"一列需二次读取取证** |

---

## 5. 阻塞项状态（按 `2c48579` 结算）

### 5.1 已闭合（原 B 系列）

| 编号 | 原待定义项 | 闭合依据 | 影响用例 |
|---|---|---|---|
| B1 | `readback_pending` 状态位与终局 | §5.7 状态枚举含 `applying`/`readback_pending`/`failed`；§6.7 + 示例 19 给出错误码与 `details` | T01、T02 |
| B2 | apply 阶段版本冲突错误码 | §6.7 判定顺序第 3 步"版本变化返回 `SNAPSHOT_CONFLICT`，以上均为零写入" | T04、T04-b |
| B3 | 提案过期错误码 | §4.1 `PROPOSAL_EXPIRED`（409）+ §6.7 + 示例 15 | T06 |
| B4 | 已应用提案重复 apply | §4.1 `ALREADY_APPLIED`（409）+ 判定顺序第 2 步 + 示例 14 | T08 |
| B8 | `approval_token` 一次性还是可重放 | §6.6/§7.1：**一次性、签发后 5 分钟、不得越过 Proposal 到期、仅交付一次** | T19、T05 |
| B10 | 单日 `skip` 语义 | §5.7：**`skip` 不属于 v1 change 白名单**，只能进 `unplanned_tasks` | T15（改为负向） |

另有两项在文本层闭合（我此前实测发现）：`duration_source` 枚举统一为 `task_target`/`scheduler_estimate`（原 F5）；`scheduled_at` 省略=保留、null=清除、跨日 `PROPOSAL_INVALID`（原 F6/P0-6）。

### 5.2 仍开（不依赖 BLOCKED，属纯文档决策）

| 编号 | 待定义项 | 影响用例 | 解除条件 |
|---|---|---|---|
| B5 | `violations[]` 项结构与 `code` 枚举 | T10-a/b、T11 | 定义封闭枚举与项 schema；当前只有空数组示例 |
| B6 | 幂等"执行中"响应 | T07 | 明确阻塞/202/409+`in_progress` 之一 |
| B7 | `FORBIDDEN` / `NOT_FOUND` 策略 | T09-b | §8 现写"由安全评审冻结"；先定"v1 统一 `NOT_FOUND`"即可解锁 |

### 5.3 新增（`2c48579` 复审发现）

| 编号 | 问题 | 级别 | 影响用例 | 解除条件 |
|---|---|---|---|---|
| B11 | `APPROVAL_CONSUMED` 可达性取决于**消费时点**，契约未定义：§6.6 把 `consumed` 释为"已成功消费"（成功即 `applied` → §6.7 第 2 步先命中 `ALREADY_APPLIED`）；唯 apply 前消费且写入失败（`failed`/`readback_pending`）时可达。另示例 16 走"他提案 + 旧 Token"路径，按 §6.7 绑定核验应判 `APPROVAL_UNTRUSTED`，示例与正文优先级冲突 | P1 | T18、T22、T03-a | 二选一：①明写"apply 进入 `applying` 时即消费 Token"，则失败路径可达；②删码保状态、重复 apply 统一 `ALREADY_APPLIED`。并改写示例 16、补消费时点一句 |
| B12 | `APPROVAL_UNTRUSTED` 全文零触发条件 | P1 | T22 | 把 §6.7 五条核验逐条绑定错误码 |
| B13 | `approved → token_issued` 未声明原子 | P2 | T21 | 契约补"该迁移原子，并发轮询仅一个响应可携带 Token" |
| B14 | `failed` 无判定条件、无错误码 | P2 | T03 | 定义"safe failure"（写入确证未发生）与对应码 |
| B15 | apply 成功响应缺 `proposal_status` | P2 | 全部（"状态"取证列） | 成功响应增加 `proposal_status=applied`；`readback_pending` 时正式字段而非仅 `details` |
| B16 | `READBACK_MISMATCH` 之后的 Proposal 终态未定义（停留 `applying` / `failed` / `readback_pending` 三选一），且与 `failed` 的"safe failure"边界重叠 | P1 | T03-a | 明确"回读结论为不一致"→ 立即 `failed`（而非 `readback_pending`，后者仅限结论不确定）；或新增 `readback_failed` 状态。§10 Q5 只覆盖"`readback_pending` 恢复流程"，未覆盖本条 |
| B17 | `approval_status` **同名双域**：§6.4 的 `validate_schedule.data.approval_status` 为 `not_requested` / `not_approvable`，与 §6.6 的 6 个审批状态零交集，同名不同义 | P2 | T16、全部含 `approval_status` 的响应 | 改名 `approvability` / `approval_hint`，或在 §5 声明为两个独立枚举、不得混用 |

### 5.4 环境性阻塞（不变）

| 编号 | 内容 | 说明 |
|---|---|---|
| B9 | 真实服务可用性 | 快照服务、可信审批、原子写入、WorkBuddy 远程 API 仍 BLOCKED；本轮不因契约修订而解除 |

在 B5–B7、B11–B15 未定之前，矩阵相关单元格保持 `[待定]`，**不替 M0 填默认值**，也不以 Mock 结果代替真实结论。

### 5.5 来自 PR #3 评审（@bbf0992 → `e7be8c9`）的增量

详见 `docs/reviews/2026-10-30-m1-pr3-review-M3.md`、`2026-10-31-m1-e7be8c9-recheck-M3.md`、`2026-10-31-m1-incremental-recheck-M3.md`。

- **T08 已解锁**：判定顺序修正后 `ALREADY_APPLIED` 可达（我在 `e7be8c9` 上实测复现）
- **T09-b 假通过风险仍在**：Mock 的 `upsert_daily_override` 不校验 item 存在性，真实服务接入前不得记 PASS
- **契约层已补齐**：实现层先修、文本层当时未修的几处，本轮 `2c48579` 已在正文补齐
- **A 的 Mock 需重做**：现行 Mock 对应旧契约，20 个错误码 / 8 个 Proposal 状态 / 6 个 Approval 状态均不对齐，旧 26/26 **不可作为新契约证据**

---

## 6. 执行与取证规则（留给后续执行时使用）

1. **写入次数**必须三路取证并一致：目标表行数差、幂等记录的执行计数、服务端应用日志的写入次数。三者不一致时以行数为准并记录差异。
2. **响应码**以实际 HTTP 状态 + `error.code` 双重记录，两者不一致视为契约缺陷（F1）。
3. 失败分三类归因，不得混为一谈：
   - **F1 契约缺陷**：契约未定义或自相矛盾，用例无法判定 → 提交 M0
   - **F2 实现缺陷**：契约明确但实现不符 → 提缺陷单
   - **F3 夹具缺陷**：前置数据或故障注入不成立 → 修用例，不计入实现质量
4. 只有在真实执行后，才允许在本文件追加"实测"列；执行依据须注明环境（Mock / 真实服务）与时间。当前环境为 **BLOCKED**，故严格执行"零实测记录"。

---

## 7. Mock 侧实测记录

> **`2c48579` 尚无对应的 Mock 实现**：仓库内现有 Mock 对应契约 `e7be8c9`（旧版，14 个错误码、无 `applying`/`failed`、无 Token TTL、`reason_code` 用旧词）。因此本轮对 `2c48579` 的复审为**纯文档级**，下节记录的是 `e7be8c9` 时期的历史实测，**不得**迁移到新契约作为证据。

### 7.1 历史记录（2026-10-31 · e7be8c9，不作为新契约证据）

> **环境：仅 Mock**（直接调用 mock 工具函数，非 MCP stdio、非实机）。执行人 C，脚本 `probe_m1_e7be8c9.py`。不得据此声称实机通过。

| 用例 | 结果 | 关键观测 |
|---|---|---|
| T08 换幂等键重复 apply | PASS | `ALREADY_APPLIED`，无二次写入 |
| T08 同键重试 | PASS | 返回缓存结果，写入次数不变 |
| T04-b validate 摘要重算 | PASS | 任务 `updated_at` 变更 → `SNAPSHOT_CONFLICT` |
| T09-b 缺事项 | PASS | `NOT_FOUND`，进程存活，后续调用正常 |
| T01/T02 回读失败与同键重试 | PASS（部分） | 标记 `readback_pending`；同键重试只重跑回读 |
| T03 回读终局 | 不可判 | 无终局状态，`readback_pending` 可无限停留 |
| T16 审批第三态 | **FAIL** | `status` 只有 `pending/approved/expired`，无第三值 |
| T17 过期审批重建 | **FAIL** | 复用死记录，提案锁死 |
| T05 审批过期 | 部分 | 轮询返回 `expired`，无 `APPROVAL_EXPIRED` 错误码路径 |
| T12-b 时长来源 | 部分 | 优先级正确，枚举命名与契约不一致 |

**2026-10-31 增量复审补充实测（队长 10 项清单）**：

| 用例 | 结果 | 关键观测 |
|---|---|---|
| T11 旧 `scheduled_at` 只改 planned_date | **FAIL** | change 缺 `scheduled_at` → 旧值被**静默清空**，回读仍判 PASS；`tool_server.py:663-664` 无条件覆盖，`:702` 两侧皆 None 故通过 |
| T09-c 既有 override 再次写入 | 需契约定义 | `override_id` 被替换（`ov_0038→ov_0063`）；真实库唯一键下必撞。回读未校验 `action`/`item_type`/`override_id` |
| T04 版本冲突零写入 | PASS | 冲突后 tasks/overrides 全量深比较无变化 |
| T01/T02 回读重试零重写 | PASS | `override_id` 与条目数均不变，仅重跑回读 |
| T17 过期审批重建 | FAIL | 复用死记录（F1） |
| Token 5 分钟边界 | **未实现** | token 记录无过期字段，永久有效 |

明细见 `docs/reviews/2026-10-31-m1-incremental-recheck-M3.md`。

明细与根因见 `docs/reviews/2026-10-31-m1-e7be8c9-recheck-M3.md`。

---

## 8. 变更记录

| 日期 | 变更 | 说明 |
|---|---|---|
| 2026-10-30 | 初版，定义 T01–T12 预期 | 仅预期，未执行；待 M0 修订状态机与错误码后复核 |
| 2026-10-30 | 追加 T15 条件式占位（单日 skip，分支 A/B）；新增 B10；补 §4.1 PR #3 评审增量 | T15 在 skip 语义定稿前不可执行；无实测记录 |
| 2026-10-31 | 新增 T04-b、T12-b、T16 | 对应 A 侧 10-31 九项修订，判据见 `docs/reviews/2026-10-31-a-fix-verification-checklist-M3.md` |
| 2026-10-31 | 新增 T17（过期审批重建）；新增 §7 Mock 实测记录 | 在 e7be8c9 上实测：T08/T04-b/T09-b 通过，T16/T17 失败，明细见 recheck 文档 |
| 2026-10-31 | 新增 §2 状态机与用例映射、T18（APPROVAL_CONSUMED 可达性）、§4.1 八项索引；T09 回读字段扩至 7 项；章节重排 | 仅定义预期与可达性，无新增实测；按队长要求保留 8 项重点 |
| 2026-10-31 | 依 M0 再次确认的固定 SHA 复核两份契约文件：加入 Git blob / SHA-256 指纹与机检结果（20 示例、8 错误响应、8/20 码覆盖、0 结构缺失）；新增 B17（`approval_status` 同名双域） | 机检可复算，非实测；误报项已复核并说明 |
| 2026-10-31 | **M0-1 固定基准增量对齐**：头部固定 SHA 与 PR；T03 拆为 T03-a（`READBACK_MISMATCH`，终态待定）/ T03-b（`READBACK_PENDING`，同键只回读）；新增 B16；B11 补"消费时点"缺失；统计改 22 编号 / 23 用例项（16/4/3） | 未改契约本体、未重跑实测；只做 C 侧用例口径对齐，明细见 `docs/reviews/2026-10-31-c-incremental-alignment-2c48579.md` |
| 2026-10-31 | **按 `2c48579` 最终稿全量重判**：§2.1/2.2 状态迁移改判（6 闭合/2 部分）、§2.3 错误码表扩至 20 个、T12-b 枚举修正、T15 改为负向用例、新增 T19–T22、§5 阻塞结算（B1–B4/B8/B10 闭合，新增 B11–B15）、§7 注明新契约无 Mock、§9 标注已执行 | **纯文档级复审，无任何实测**；结论见 `docs/reviews/2026-10-31-m0-final-2c48579-incremental-M3.md` |

## 9. 单次增量复审清单（已于 `2c48579` 执行一次）

> **执行状态：已完成（2026-10-31）**。执行记录与结论见 `docs/reviews/2026-10-31-m0-final-2c48579-incremental-M3.md` §9。
> 下次 M0 再发新 commit 时，仅按本清单复跑一次，**不再重开全量评审**。

> 队长要求：新契约 commit 发布后**只做一次**增量复审。执行时按本节顺序走完即可，不重复全量评审。

1. **固定版本**：记录新 commit 的 40 位 SHA，全流程只认这一个版本。
2. **状态可达性（8 项）**：按 §2.1 / §2.2 / §4.1 逐条确认——表中标 `[未定义]` 的 7 个迁移是否已补状态值；`[未定义]` 清零即视为状态机就绪。
3. **错误码可达性（8 个）**：按 §2.3 表逐条实测，**只认"能触发"不认"文档里有"**（G1 原则）。
4. **四元组复核**：对 §4.1 索引的每个用例填「响应码 + 状态 + 数据 + 写入次数」，任一不符即记缺陷。
5. **契约正文一致性**：核对 §4.1 错误码表、§5.7 状态枚举、`get_approval_status` 状态机三处是否与本矩阵用词一致（`duration_source` 枚举需同时统一）。
6. **归档**：本次实测写入 §7，注明环境（Mock / 真实服务）与 SHA；旧的 e7be8c9 记录标记「历史」，不得混用。
7. **输出**：一页结论（同意冻结 / 有条件同意 / 反对）+ 未验证项清单，不重复粘贴全量证据。
