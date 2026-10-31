# M0 Agent API v1 验收矩阵（T01–T22 + R1/X1/G1–G5/S1 + V1/Y1）

- **归属**：M3 / Evaluation（同学 C）
- **固定基准（现行）**：`c53b1a91c17cd9acdee6d3937c093fcf97515ba0`（分支 `feat/m0-api-contract`，PR **#4** 当前 head，2026-10-31 23:24 由队长提交，7 工具 / 21 错误码 / 45 个远程示例）
- **历史基准**：`2c48579…` 及其上的全部判定自 2026-11-01 起只作历史证据，不再作为现行契约引用（队长邮件指令）
- **基准唯一性**：C 侧全部用例与判定只认现行 SHA；M0 再发新 commit 时按 §9 重跑一次，不混用旧版本结论
- **状态**：**预期定义阶段，尚未执行任何一条**（含本轮新增的 5 条）
- **本轮增量**（2026-10-31 队长 6 项）：新增 §3B 的 R1、X1、G1、G2、S1；第 6 项"写入次数"落为 §6.2 的四层口径。队长第二次要求"补充 B19 语义验收"后，扩 G3（null）/G4（语义隔离）/G5（低于最小块长）三条，把 `remaining_minutes_today` 的四种预算值封成一组对照。**只增量追加，未重审旧问题、未改 M0 契约本体、无新增实测**
- **第三轮增量**（2026-11-01，新 SHA `c53b1a9`）：按队长邮件 7 项要求做增量对齐——B5/B6/B7/B11–B18 全部解除（见 §5），T03-a/T07/T09-b/T10/T18/T21/T22/X1/G2 改判可判，EX-17 改判可执行，新增 V1/Y1 两条；**仍未执行任何一条，全部结论为 E0 静态判据**
- **纪律**：本文件只写"输入"与"预期"。所有预期列都是**待验证的断言**，不是实测结果。执行后再另开一节回填实测值，本文件在此之前不得被引用为"已通过"。
- **复核时点**：`2c48579` 已完成一次增量复审（`docs/reviews/2026-10-31-m0-final-2c48579-incremental-M3.md`）；M0 将其作为 Task 1 固定基准发布（PR M0-1）后，按 C 口径完成**增量对齐**（`docs/reviews/2026-10-31-c-incremental-alignment-2c48579.md`），未重开全量审计、未重跑实测。

判定口径统一为四元组：**响应码 + Proposal 状态 + 数据结果 + 实际写入次数**。四项全部吻合才算 PASS。每条结论还必须带**证据级别**（E0–E3，见 §6.1）——"通过"不带级别不接受。

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
| `applying` / `readback_pending` 保持原状态 | **换新幂等键**再 apply → `READBACK_PENDING`、零写入 | X1 | **未定义（B18，P0）**：判定顺序第 1–2 步均不命中，契约未约束"新键"，实现会重写 |

### 2.2 Approval（6 个状态值）

| 迁移 | 触发 | 对应用例 | 契约定义情况 |
|---|---|---|---|
| 创建 → `pending` | `request_approval` | T16 | 已定义（§6.5） |
| `pending` → `approved` | 外部确认通过 | T16 | 已定义（§6.6） |
| `approved` → `token_issued` | 首次安全交付 Token | T19、T21 | 已定义（§6.6）；**并发交付原子性未写**（P2-2） |
| `token_issued` → `consumed` | apply 成功消费 | T18 | 状态已定义，但对应错误码不可达（P1-1） |
| `pending` → `expired` | 审批或 Token 过期 | T05 | 已定义（§6.6，区分"仅 Token 过期"与"Proposal 也过期"） |
| `expired` → 新审批 | 再次 `request_approval` | T17、**R1** | **部分**：允许重建（§6.6 明文"可以重新创建审批，但旧 Token 永远无效"），但未定返回新/旧 `approval_id` |
| 任意 → `rejected` | 用户拒绝 | T16 | 已定义（§6.6） |

> **注意同名双域**：本节 6 个状态仅指 `get_approval_status.data.status`。`validate_schedule.data.approval_status` 是**另一套**枚举（`not_requested` / `not_approvable`，§6.4），两者零交集，见 B17。

### 2.3 错误码 × 可达性（§4.1 共 21 个，`c53b1a9` 新增 `IDEMPOTENCY_IN_PROGRESS`）

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

## 3B. 本轮增量用例（M0 契约调整后，2026-10-31 队长 6 项）

> 来源：队长本轮同步的 6 条。编号前 2 条由队长指定（`R1`、`X1`），后 3 项按语义另编（`G`=generate 排程预算，`S`=Schema 序列化）。第 6 项（写入次数）不是用例，是取证口径，见 §6.2。
> 本轮**只增量追加**，不重审旧问题、不改 M0 契约本体；全部为预期定义，**零实测**。

### R1 Token 过期但 Proposal 仍有效 → 重建审批必须换 `approval_id`，旧 Token 永久失效

- **输入**：`P_1` 于 `T0` 生成（TTL 30 分钟）；`T0+2min` 外部批准并**首次交付** Token `TK_1`（`token_expires_at=T0+7min`）。在 `T0+8min`（Token 已过期、Proposal 仍剩 22 分钟）依次执行：(a) 用 `TK_1` apply；(b) `get_approval_status(A_1)`；(c) 对 `P_1` 再次 `request_approval` 得 `A_2` 并交付 `TK_2`；(d) 再用 `TK_1` apply；(e) 用 `TK_2` apply
- **预期响应码**：(a) `APPROVAL_EXPIRED`（403）；(b) `success` + `status=expired`；(c) `success` + `approval_id=A_2`（`≠A_1`）+ `status=pending` + `expires_at` 在未来；(d) `APPROVAL_EXPIRED`（403）——**旧 Token 不得因新审批而复活**；(e) `success`
- **预期 Proposal 状态**：全程 `pending_approval`，仅 (e) 后转 `applied`；**不得**因 Token 过期而进入 `expired`
- **预期数据结果**：`A_1` 落库为 `expired`（**持久化值**，不是查询时即时计算）；`A_1.token_expires_at` 保持 `T0+7min`，不被 `A_2` 继承或延长；`TK_2` 与 `TK_1` 值不同；审批表 `A_1`、`A_2` **两条并存**（不是覆盖同一行）
- **预期写入次数（W4）**：(a)(b)(d) 目标表 **0**；(c) 审批表 **+1 行**；(e) 目标表 **1**
- **判定要点**：契约 §6.6 有两句明文支撑——「若仅 5 分钟 Token 过期而 Proposal 仍有效，Proposal 保持 `pending_approval`，可以重新创建审批，**但旧 Token 永远无效**」。故本条**大部分可判**；唯一推断项是 `A_2 ≠ A_1`（§6.5 的幂等只约束"已有**未终结**审批"，过期属已终结）。`e7be8c9` 在 (c) 会复用 `A_1`（F1/F2 的根因），导致 (d) 仍报过期、(e) 无可用凭据 → 提案锁死，是本条最真实的反例
- **与 T17 / T19 的边界**：T17 是**审批记录**过期后重建；T19(a) 只验"Token 过期时 Proposal 不进 `expired`"；R1 验的是**过期后重建的凭据隔离**——三者断言不重叠，不可互相替代
- **可顺带取证的分支（不计入本条判定）**：§6.6 另规定"若交付响应丢失，v1 不重新显示原 Token，必须废止旧审批并在 Proposal 仍有效时重新走审批"。执行 `get_approval_status` 时应确认 `status=token_issued` 且 `approval_token=null`，与 (c)(d) 属同一断言族

### X1 Proposal 处于 `applying` / `readback_pending`，换新幂等键 → `READBACK_PENDING`，零写入

- **输入**：`P_1` 已 approve 并 apply，写入可能已提交但回读未决（由 T01 / T03-b 构造 `readback_pending`；另注入写入未返回以构造 `applying`）。在两个时点各发起一次 apply，**每次都换全新的 `idempotency_key`**：(a) `status=readback_pending` 时用 `K_new1`；(b) `status=applying` 时用 `K_new2`
- **预期响应码**：(a)(b) 均为 `READBACK_PENDING`（503）；**不得** `ALREADY_APPLIED`（Proposal 并未 `applied`）、**不得** `success`、**不得** `INTERNAL_ERROR`
- **预期 Proposal 状态**：分别保持 `readback_pending` / `applying`，不回退、不因新键请求跳入 `applied`
- **预期数据结果**：目标表零新增、零修改；`override_id` 集合与字段指纹完全不变；**幂等记录不得因新键新增执行条目**（新键只允许被登记为"被拒"，不得产生执行记录）
- **预期写入次数（W4）**：**0**（这是本条唯一不可让步的断言）
- **分级判定**：
  - (i) 码 = `READBACK_PENDING` 且 W4 = 0 → **PASS**
  - (ii) 码为其他但 W4 = 0 → **部分**（安全性守住、码不符，记 B18）
  - (iii) W4 > 0 → **FAIL（P0）**，无论返回什么码。这是"同一 Proposal 被二次应用"，直接违反 §6.7「换一个幂等键也不能再次应用同一 Proposal」
- **判定要点**：契约 §5.7 只约束「**同一**幂等请求继续回读」，§6.7 的"最多成功应用一次"只覆盖**已成功**的 Proposal——`applying`/`readback_pending` 属于"尚未成功"，两条都不覆盖，是**契约真空（B18）**。队长本轮补的口径正好补上这个洞
- **风险提示**：新幂等键天然**绕过**幂等缓存。实现若把"查幂等记录"当作唯一的重放防线，本条必挂——这是 `e7be8c9` 完全没有走过的新路径

### G1 `remaining_minutes_today=0` → 不生成 block，且不进入 `unplanned_tasks`

- **输入**：`T_RE_1`（周期 `daily`，`duration_target_seconds=3600`）当天 `remaining_minutes_today=0`；`generate_schedule`（服务端可信快照）→ `validate_schedule`
- **预期响应码**：两次均 `success`
- **预期 Proposal 状态**：`draft`（validate 通过后 `pending_approval`）
- **预期数据结果**：`blocks` 中**无该 task**；`unplanned_tasks` 中**也无该 task**；`explanations` 若提及该 task，`code` 不得使用 `WINDOW_INSUFFICIENT` / `NO_AVAILABILITY` 等"排不下"语义；同 snapshot 内其他 task 正常成块
- **预期写入次数（W4）**：**0**（`generate_schedule` 与 `validate_schedule` 均不写库）
- **判定要点**：契约 §5.2「为 `0` 时当天不再排程」、§5.6「为 `0` 时不生成 block」——**前半句明文可判**。**后半句（不进 `unplanned_tasks`）未明文**：§5.7 把 `unplanned_tasks` 定义为"**无法安排**的 Task"，且写明"未安排不等于完成或跳过"；`remaining=0` 的语义是"今日目标已完成/无需再排"，不是"排不下"。塞进 `unplanned_tasks` 会把"已完成"误报为"失败"，并污染 `reason_code` 统计——记 **B19**。反证也成立：`reason_code` 四个枚举值没有一个是"已完成"
- **可判性**：**可判**（队长口径与契约语义双向支持；B19 只影响 M0 是否补一句明文，不影响本条判定）

### G2 `remaining_minutes_today=40` → 只生成 40 分钟排程

- **输入**：同上，`remaining_minutes_today=40`（`duration_target_seconds=3600`）；`preferences` 两组：默认（不传 `minimum_block_minutes`）与显式 `30`
- **预期响应码**：`success`
- **预期 Proposal 状态**：`draft`
- **预期数据结果**：该 task **恰好 1 个 block**，`duration_seconds=2400`（**精确值，不设容差**；`task_target` 来源不存在估算误差），`duration_source=task_target`，`end_at - start_at = 2400s` 且同属一个上海本地日；`unplanned_tasks` 无该 task；可持久化时 `planned_end_minute - planned_start_minute = 40`；`duration_target_seconds` 保持 3600（**不得被 40 覆盖**）
- **预期写入次数（W4）**：**0**
- **判定要点**：契约 §5.6 只明文"`null` 用完整目标、`0` 不生成 block"，**未明文"非 0 值即上限"**——属单调性推断，记 **B19** 第二条。三个高频错误：① 仍按 3600s 成块（`duration_seconds` 不符）；② 用 `scheduler_estimate` 回填（`duration_source` 不符）；③ 把 40 分钟写回 `duration_target_seconds`（违反"估算不得写回持久化字段"）
- **边界提示（不新增用例）**：若 `preferences.minimum_block_minutes=45`，40 分钟无法达到最小块长，此时应入 `unplanned_tasks`（`WINDOW_INSUFFICIENT`）而不是生成 40 分钟块——**与默认组结论相反**。执行前必须先固定该 preference 并写进证据，否则结果不可复现

### G3 `remaining_minutes_today=null` → 使用完整目标 3600s（B19 语义对照）

- **输入**：`T_RE_1`（`duration_target_seconds=3600`）当天 `remaining_minutes_today` 字段**缺失或为 `null`**；`preferences` 默认；`generate_schedule` → `validate_schedule`
- **预期响应码**：两次均 `success`
- **预期 Proposal 状态**：`draft`
- **预期数据结果**：该 task **恰好 1 个 block**，`duration_seconds=3600`（精确），`duration_source=task_target`；`unplanned_tasks` 无该 task；`duration_target_seconds` 保持 3600
- **预期写入次数（W4）**：**0**
- **判定要点**：契约 §5.6 明文「该字段为 `null` 时使用完整目标」——**完全可判**，是本组唯一不需要推断的一条。它与 G1（0→不成块）、G2（40→截断）构成三态对照：**同一任务的三种预算值应产生三种不同 block 数/时长**，任何两种结果相同都说明预算字段未被真正消费
- **与 S1 的关系**：G3 同时验证 `blocks[].duration_seconds` 与 `end_at - start_at` 一致，可作为 S1 的字段级交叉校验

### G4 「无需安排」与「排不下」的语义隔离（B19 核心）

- **输入**：同一 snapshot 内两个周期任务——`T_RE_1` 当天 `remaining_minutes_today=0`、`T_RE_3` 当天 `remaining_minutes_today=120` 但可用窗口只剩 30 分钟（不足 ≤ `minimum_block_minutes` 时可成的块）；一次 `generate_schedule`
- **预期响应码**：`success`
- **预期 Proposal 状态**：`draft`
- **预期数据结果**：
  - `T_RE_1`（=0）：**不在 `blocks`**，**不在 `unplanned_tasks`**，`explanations` 中不得出现任何"排不下"语义的 `code`
  - `T_RE_3`（窗口不足）：**在 `unplanned_tasks`**，`reason_code=WINDOW_INSUFFICIENT`，且带 `remaining_minutes`
  - 两者的处理**必须可直接区分**：一个"未出现"、一个"出现在未安排列表里"
- **预期写入次数（W4）**：**0**
- **判定要点**：这是 B19 的实质——`unplanned_tasks` 的语义是"**无法安排**"，`remaining=0` 是"**无需安排**"。若实现把两者都塞进 `unplanned_tasks`，统计上会把"今日已完成"记成"排不下"，`reason_code` 分布失真；若实现把 `T_RE_3` 也悄悄丢掉，则用户永远看不到"因为窗口不够没排上"。本条同时抓两种错
- **可判性**：**可判**（`WINDOW_INSUFFICIENT` 是 §5.7 四值之一，语义明确；"=0 不入列"由队长口径 + B19 反证支撑）

### G5 `remaining_minutes_today=20` < 最小块长 → 第三态（B19 边界）

- **输入**：`T_RE_1` 当天 `remaining_minutes_today=20`；`preferences.minimum_block_minutes=30`（显式）；`generate_schedule`
- **预期响应码**：`success`
- **预期 Proposal 状态**：`draft`
- **预期数据结果**：**不得**生成 20 分钟的 block（低于最小块长）；该 task 应进入 `unplanned_tasks`，`reason_code=WINDOW_INSUFFICIENT`，`remaining_minutes=20`；`duration_target_seconds` 不变
- **预期写入次数（W4）**：**0**
- **判定要点**：B19 的第三态。契约只写了 0（不成块）与 null（用完整目标），**没写"非 0 但低于最小块长"怎么办**——是"入 `unplanned_tasks`（排不下）"还是"按最小块长强行排 30 分钟（超预算）"还是"忽略该任务"，三种都说得通。C 侧按"不得超预算 + 不得静默丢弃"取最保守预期：入 `unplanned_tasks` 并给 `WINDOW_INSUFFICIENT`
- **与 G2 的对照**：40 分钟 > 30 → 正常成块；20 分钟 < 30 → 不成块。两条一起才说明 `minimum_block_minutes` 真的生效，而不是被忽略
- **可判性**：**部分可判**——"不得超预算"可判（预算语义），"必须入 `unplanned_tasks`"属推断，需 M0 在 B19 的第二句里明确

### S1 Proposal 序列化：只认服务端组装后的完整 Schema，不认 M2 DTO 解析成功

- **输入**：抓取 `generate_schedule` 与 `validate_schedule` 的**原始 HTTP 响应体**（不经任何 SDK / DTO / ORM 中转），逐字段校验 `schedule_proposal`
- **预期响应码**：`success`
- **预期 Proposal 状态**：`draft`
- **预期数据结果**：按 §5.7 逐字段核验——
  - 必填齐全：`proposal_id`、`snapshot_ref`、`base_version`、`input_digest`、`status`、`generated_at`、`expires_at`、`blocks`、`changes`、`unplanned_tasks`、`explanations`
  - `status` ∈ 8 值；`blocks[].source` 固定 `proposal`；`persistable_as` ∈ 2 值；`duration_source` ∈ 2 值；`duration_seconds` 为正整数且等于 `end_at - start_at`
  - `unplanned_tasks[].reason_code` ∈ 4 值；`explanations` 每项为**对象**（不得字符串与对象混用），含机器可读 `code` + 安全 `message`
  - 所有时间均为带明确偏移的 RFC 3339；`input_digest` 为小写十六进制 SHA-256
- **预期写入次数（W4）**：**0**
- **判定要点**：**M2 内部 DTO 反序列化成功，不得作为 Schema 合规证据**。Dart 的 `fromJson` 通常给字段默认值、容忍缺失、忽略未知字段，服务端漏 `input_digest` 也可能解析通过——这类"DTO 宽松解析"会把契约缺字段藏成"看起来正常"
- **负向对照（必做，否则本条的取证方式不成立）**：人为从响应中删掉一个必填字段（如 `input_digest`）或把一个 `explanations` 项改成字符串，若 M2 DTO 仍解析成功且界面无报错 → 证明 DTO 校验无效，本条只能用"原始 JSON + 独立校验器"取证
- **附 E0 静态证据（不混入本条执行结果）**：契约 §5.7 字段表 vs M2 DTO 字段名/枚举做一次逐项比对，差异单列

## 3C. 第二轮对齐（`c53b1a9`）：改判表与新增用例

**本表覆盖 §3B 各条中"待 M0 补句"的旧注记**；各用例正文保留不改，以本表为准。全部为静态对齐（E0），未执行。

### 3C.1 改判（9 条升为可判）

| 用例 | `2c48579` 判定 | `c53b1a9` 判定 | 依据（新契约原文位置） |
|---|---|---|---|
| X1 | 部分（契约真空，B18 P0） | **可判** | §6.7 明文："新键但 Proposal 为 `applying` 或 `readback_pending`：统一返回 `READBACK_PENDING`，零业务写入"。**B18 解除** |
| T18（EX-17） | 不可判（`APPROVAL_CONSUMED` 不可达） | **可判** | 判定顺序第 5 步：已 `applied` → `ALREADY_APPLIED`；未 `applied`（含 `failed`）→ `APPROVAL_CONSUMED`，且明文"这保证 `APPROVAL_CONSUMED` 有独立可达路径"。A 的 EX-17 自评"不可执行"按新契约**改判可执行** |
| T22 | 不可判（`APPROVAL_UNTRUSTED` 零触发） | **可判** | §6.7 末段列全触发条件：格式无效/签名失败/主体不匹配/绑定不匹配/撤销；并划清与 `APPROVAL_REJECTED` 的边界（消费前撤回 → REJECTED）。执行仍依赖可信签名服务（BLOCKED），上限 E1 |
| T09-b | 不可判（B7 未定） | **可判** | §4.1 末新增防枚举规则："资源不存在与资源属于其他用户统一返回完全相同的 `NOT_FOUND`"。**B7 解除** |
| T03-a | 部分（终态未定，B16） | **可判** | §6.7 明文：`READBACK_MISMATCH` 必含 `proposal_status=failed`；"回读确认不一致时转为 `failed` 并返回 `READBACK_MISMATCH`，不允许再次写入"。**B16 解除** |
| T07 | 部分（执行中响应未定，B6） | **可判** | §4.1 新码 `IDEMPOTENCY_IN_PROGRESS`（409，`retryable=true`）+ §6.7"同键同摘要且记录正在 `applying`"。**B6 解除** |
| T10 | 部分（violations 无结构，B5） | **可判** | 新增 §5.8：统一对象结构 + 七值闭集 + 未知 code 以 `PROPOSAL_INVALID` 拒绝。**B5 解除** |
| T21 | 部分（原子性未声明，B13） | **可判** | §6.6"并发 `get_approval_status` 必须对 Token 交付做原子认领：最多一个请求取得非空 `approval_token`"。**B13 解除** |
| G2 | 部分（非 0 上限属推断，B19） | **可判** | §5.2 内部 Fixture 2 明文：`remaining_minutes_today=40` 且完整 `duration_target_seconds=7200` → 40 分钟 block、`duration_seconds=2400`、`duration_source=task_target`。**注意 fixture 的目标时长由 3600 换为 7200，执行时输入要换** |

其余三条改判（非升降级，口径更新）：

- **R1**：由"推断新 `approval_id`"升级为**两句明文支撑**（§6.6："可以重新创建审批，但旧 Token 永远无效"；统一过期边界 `now >= expires_at` 解决了 `>=` vs `>` 之争）。"重建返回新 `approval_id`"仍属实现必然但未逐字写明，执行时若返回旧 ID 记 FAIL。
  - **复核修正**（`docs/reviews/2026-10-31-m0-c53b1a9-incremental-M3.md` §1）：重建的前置是"旧 Approval 已终结 + **用户明确要求**"（§6.5/§6.6）；"用户明确要求"属可信意图验证 → **BLOCKED**。R1 的状态机部分（旧 Token 永久失效、Proposal 不进 `expired`）可判，执行上限 E1。
- **G1**：由"明文+反证"升级为**完整明文**：`remaining_minutes_today=0` → 不生成 block、**不进入 `unplanned_tasks`**、仅产生 `ALREADY_DONE_TODAY` explanation、不得进入最低时长兜底。G1/G4 必须断言 `explanations[].code=ALREADY_DONE_TODAY`（回应 M1/M2 枚举分歧）。
- **S1**：由"字段表推断"升级为**方案 A 明文**：M2 纯函数不得生成/输出 `proposal_id`、`snapshot_ref`、`base_version`、`input_digest`、`generated_at`、`expires_at`、`status` 七字段，由服务端包装层组装。负向对照（删必填字段 DTO 仍能解析）判据不变。

### 3C.2 新增用例（2 条，`c53b1a9` 新文本）

**V1 `violations` 七值闭集与未知 code 拒绝**

- **输入**：构造 block 计划日期早于 `available_from`（命中 `PLANNED_BEFORE_AVAILABLE_FROM`）与一个未知 code（如 `MY_NEW_VIOLATION`）各一次
- **预期四元组**：合法违规项按 §5.8 对象结构（code/message/可选 related_*）原样返回；未知 code 的 Proposal 整体以 `PROPOSAL_INVALID` 拒绝，**不得**把未知码透传进 violations；两次均零写入
- **依据**：§5.8"公开 `code` 的 v1 完整闭集仅为…未知 `code` 必须以 `PROPOSAL_INVALID` 拒绝"
- **可判性**：可判（E0 起）

**Y1 同键执行中重试 → `IDEMPOTENCY_IN_PROGRESS`**

- **输入**：apply 请求 A 进入 `applying` 后（写入未落定），用**同一幂等键同摘要**立即重试 B
- **预期四元组**：B 得 HTTP 409 + `IDEMPOTENCY_IN_PROGRESS` + `retryable=true`；Proposal 仍 `applying`；W4 增量为 0（B 不得启动第二次写入，也不得无限等待）；随后 A 的终局不受 B 影响
- **依据**：§4.1 码表 + §6.7"零业务写入且不得无限等待"
- **可判性**：可判（E0 起）

### 3C.3 Token 交付不确定（队长邮件第 2 项，口径替换）

旧假设"服务端可主动替换/重发 Token"**作废**。`c53b1a9` §6.6 明文：交付响应丢失时 v1 **不重新显示、不撤销、不替换**原 Token，等待其按 5 分钟 TTL 自然过期；仅**用户明确要求**后才能在 Proposal 仍有效时重新走普通审批（新 `approval_id`、新审批记录，旧 Token 永久无效）。并发原子认领语义见 T21。真实签名/交付身份仍 **BLOCKED**。

R1、T17、T19 与本节的分工：R1 验证"过期后重建"的凭证隔离；T17 验证审批记录过期后可重建；本节验证"**交付丢失**"路径——三者入口不同，不得互相替代。

---

## 4. 覆盖对照（`2c48579` 首判，`c53b1a9` 改判——见 §3C 改判表）

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
| Token 过期后重建凭据（本轮） | R1 | **可判**（§6.6 两句明文；仅"新 `approval_id`"属推断） |
| 非终态 + 新幂等键（本轮） | X1 | **部分可判**——零写入可判，响应码属契约真空（B18）；W4>0 直接 FAIL |
| `remaining_minutes_today=0`（本轮） | G1、G4 | **可判**——不生成 block 明文；"不入 `unplanned_tasks`"由队长口径 + `reason_code` 反证支撑（B19） |
| `remaining_minutes_today=40`（本轮） | G2 | **部分可判**——「截断为上限」属推断（B19）；需先固定 `minimum_block_minutes` |
| `remaining_minutes_today=null`（B19 扩展） | G3 | **可判**——§5.6 明文「`null` 用完整目标」，与 G1/G2 构成三态对照 |
| `remaining_minutes_today=20`（B19 边界） | G5 | **部分可判**——「不得超预算」可判，「必须入 `unplanned_tasks`」属推断 |
| Proposal 完整 Schema（本轮） | S1 | **可判**（§5.7 字段表完整）；须脱离 M2 DTO 取证 |

附两条低成本用例：T13 请求体带 `user_id` → `INVALID_ARGUMENT`；T14 空任务/空日历 → `success` + 空数组（不得 404）。

**统计（32 个编号 / 33 个用例项，T03 已拆 a/b）**：完全可判 **32**、部分可判 **1**（G5，低于最小块长仍无明文）、不可判 **0**。

相比 `2c48579` 轮（21/7/3）：`c53b1a9` 把 9 条升为可判（T03-a、T07、T09-b、T10、T18、T21、T22、X1、G2），新增 V1/Y1 两条可判，G5 是唯一残留（B19 缺口）。**"可判"指判据完备、可以执行，不等于已执行**；全部用例当前最高证据级别仍为 E0，四项 BLOCKED（base_version、可信审批、原子写入、生产回读）未解除。

演进：`2c48579` 首轮 15/3/4 → 上轮 16/4/3（T03 拆分）→ 队长 6 项后 19/6/3 → 本轮补 B19 语义后 **21/7/3**。新增 R1、G1、G3、G4 入完全可判，X1、G2、G5 入部分可判。**全部 31 项零实测**。

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

### 4.2 不属于本矩阵的范围：任务拆解质量（DA01–DA15）

计划 D3 要求「检验任务拆解质量，覆盖不合理拆解、模糊截止日期」，但 v1 契约的 7 个工具**没有拆解工具**——拆解发生在 Agent 层，产物才进入 `generate_schedule`/`validate_schedule`。契约未定义子任务结构，因此拆解不合格无法判定为「实现缺陷」还是「契约缺项」，**不并入 T 系列**。

单列 15 条 DA 用例，判据见 `docs/contest/decomposition-acceptance.md`，数据见 `fixtures/education/decomposition_cases.json`。当前零执行，状态全部为「未执行」。唯一交集是写入安全：DA14/DA15 与 T15 同源（未确认不得写库），但入口不同（Agent 层 vs 契约工具链）。

---

## 5. 阻塞项状态（按 `c53b1a9` 结算）

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

### 5.2 已闭合（第二轮，`c53b1a9` 落笔）

原"仍开"三条全部解除：

| 编号 | 原待定义项 | 闭合依据（`c53b1a9` 原文） |
|---|---|---|
| B5 | `violations[]` 项结构与 `code` 枚举 | 新增 §5.8：统一对象结构 + 七值闭集 + 未知 code → `PROPOSAL_INVALID` |
| B6 | 幂等"执行中"响应 | 新码 `IDEMPOTENCY_IN_PROGRESS`（409，`retryable=true`）+ §6.7 同键执行中重试条款 |
| B7 | `FORBIDDEN` / `NOT_FOUND` 策略 | §4.1 末防枚举规则："资源不存在与资源属于其他用户统一返回完全相同的 `NOT_FOUND`" |

### 5.3 第二轮复审发现 → `c53b1a9` 结算

`2c48579` 轮发现的三项（B11/B12/B13）与两轮评审累积的 B14–B18，**全部在新契约落笔解除**：

| 编号 | 原问题（级别） | 解除依据（`c53b1a9` 原文） |
|---|---|---|
| B11（P1） | `APPROVAL_CONSUMED` 消费时点未定义、不可达 | §6.7 判定顺序第 5 步 + 明文"这保证 `APPROVAL_CONSUMED` 有独立可达路径"；`failed` + 已消费 Token 也返回该码且 `retryable=false` |
| B12（P1） | `APPROVAL_UNTRUSTED` 零触发条件 | §6.7 末段列全五类触发；划清与 `APPROVAL_REJECTED`（消费前撤回）的边界 |
| B13（P2） | `approved → token_issued` 未声明原子 | §6.6"atomic token claim"：最多一个请求取得非空 Token，其余 `approval_token=null` |
| B14（P2） | `failed` 无判定条件 | §6.7："只有能够确认事务未提交的确定性失败才可直接进入 `failed`；无法确认时必须保留 `readback_pending`" |
| B15（P2） | apply 成功响应缺 `proposal_status` | §6.7 成功 `data` 明文含 `proposal_status`（固定 `applied`）；`READBACK_PENDING` 详情必含 `proposal_status=readback_pending` |
| B16（P1） | `READBACK_MISMATCH` 后终态未定义 | §6.7："确认不一致时转为终态 `failed` 并返回 `READBACK_MISMATCH`，不允许再次写入"；`recovery_evidence`（`readback_only`/`business_write_count_delta=0`/`second_apply_executed=false`）覆盖三条恢复路径 |
| B17（P2） | `approval_status` 同名双域 | §6.4 改名 `approval_readiness`（`not_requested`/`not_approvable`），并声明"只表达能否进入审批，不表达真实 Approval 生命周期" |
| B18（**P0**） | 非终态 + 新幂等键 = 契约真空，必写两次 | §6.7 明文堵死（双向）：同键回读-only；"新键但 `applying`/`readback_pending` → `READBACK_PENDING`，零业务写入" |

**B19（P1，收窄但未闭合）**：`remaining_minutes_today` 语义。已闭合部分——`=0` 三条明文（不成块、不入 `unplanned_tasks`、仅 `ALREADY_DONE_TODAY`，回应 M1/M2 枚举分歧）；`=40` 作为上限的 Fixture 明文（配 `duration_target_seconds=7200` → 2400s）；`null` → 完整目标（§5.6）。**仍缺一句**："非 0 但低于 `minimum_block_minutes`"的第三态（G5）无明文，`preferences.minimum_block_minutes` 只在 §6.6 工具表出现、其与预算的交互未定义。解除条件：§5.2 Fixture 3 或一句"低于最低块长时进入 `unplanned_tasks` 并标记 `WINDOW_INSUFFICIENT`"。


### 5.3B 第二轮新发现（`c53b1a9` 上的新问题，2026-11-01）

| 编号 | 问题 | 级别 | 影响用例 | 解除条件 |
|---|---|---|---|---|
| **B20** | **契约内部硬冲突（机检可判）**：§4.1 明文"READBACK_PENDING 错误详情**必须**包含 `proposal_status=readback_pending`"，而 §6.7 规定新键 + `applying` 也返回 `READBACK_PENDING`；示例 31 的详情实际为 `proposal_status=applying`——同一响应码在合法路径下不可能同时满足两句 | **P1** | X1、T03-b、Y1 | 二选一：§4.1 放宽为 `proposal_status ∈ {applying, readback_pending}`，或 `applying` 分支另给码（不建议，破坏零写入统一语义）。**B20 未定前，相关断言写"容忍两种状态值"，不写死** |
| B21 | 零写入证据形状不对称：`readback_pending → applied` 用 `data.recovery_evidence` 对象（示例 44），`→ failed` 把同三字段塞进 `error.details`（示例 45），无 `recovery_evidence` 对象 | P2 | T02、T03-a | failed 分支也返回 `recovery_evidence`；W4 断言暂需两套解析分支 |
| B22 | `failed` 终态 + 无有效凭据时无码：步骤 4 只规定"`failed` + 同 Proposal 已消费 Token → `APPROVAL_CONSUMED`"；`failed` + 缺 Token / 他提案 Token 的响应码未定义 | P2 | T18、T22 | 补一句优先级（建议：绑定核验在前 → `APPROVAL_UNTRUSTED`；缺凭据 → `APPROVAL_REQUIRED`） |
| B23 | 判定顺序步骤 3（幂等摘要）与步骤 4（Proposal 状态）优先级未声明：已 `applied` + 同键不同摘要，按步骤 3 → `IDEMPOTENCY_CONFLICT`，按 §6.7 末段 → `ALREADY_APPLIED`；两者都零写入但响应码不同 | P2 | T08、T07 | 一句优先级声明（建议：终态检查先于摘要冲突，`applied` 优先返回 `ALREADY_APPLIED`） |

### 5.4 环境性阻塞（不变）

| 编号 | 内容 | 说明 |
|---|---|---|
| B9 | 真实服务可用性 | 快照服务、可信审批、原子写入、WorkBuddy 远程 API 仍 BLOCKED；本轮不因契约修订而解除 |

文档级阻塞已全部闭合（G5 残留除外）。矩阵相关单元格不再有 `[待定]`；执行层阻塞（§5.4）未变，**不以 Mock 结果代替真实结论**。

### 5.5 来自 PR #3 评审（@bbf0992 → `e7be8c9`）的增量

详见 `docs/reviews/2026-10-30-m1-pr3-review-M3.md`、`2026-10-31-m1-e7be8c9-recheck-M3.md`、`2026-10-31-m1-incremental-recheck-M3.md`。

- **T08 已解锁**：判定顺序修正后 `ALREADY_APPLIED` 可达（我在 `e7be8c9` 上实测复现）
- **T09-b 假通过风险仍在**：Mock 的 `upsert_daily_override` 不校验 item 存在性，真实服务接入前不得记 PASS
- **契约层已补齐**：实现层先修、文本层当时未修的几处，本轮 `2c48579` 已在正文补齐
- **A 的 Mock 需重做**：现行 Mock 对应旧契约，20 个错误码 / 8 个 Proposal 状态 / 6 个 Approval 状态均不对齐，旧 26/26 **不可作为新契约证据**

---

## 6. 执行与取证规则（留给后续执行时使用）

### 6.1 证据分级（E0–E3，只升不跳）

> 队长本轮明确要求：**必须区分静态结论、Mock 证据、隔离测试证据和真实服务端证据**。任何"通过"都必须带级别，例如 `PASS(E1)`。

| 级别 | 名称 | 定义 | 能证明 | 不能证明 |
|---|---|---|---|---|
| **E0** | 静态结论 | 读契约 / 读代码 / 算哈希 / 引用行号，**无任何运行** | 文档存在、枚举值域、代码分支存在 | 分支**能否被触发**、行为正确性 |
| **E1** | Mock 证据 | 进程内直接调用 mock 工具函数或 M2 纯调度函数，无传输层 | 函数级分支逻辑、返回结构 | HTTP 层、鉴权、真实持久化、并发 |
| **E2** | 隔离测试证据 | 真实 HTTP 或 MCP stdio + 真实（隔离库）存储，**无生产依赖** | 错误码真实可达、写入真实落库、幂等真实生效 | 生产认证、可信审批回调、生产回读、生产并发 |
| **E3** | 真实服务端证据 | 真实认证 + 真实外部确认回调 + 生产回读 + 原子写入 | 生产可用性 | — |

**五条硬规则**：

1. 结论必须写级别；不带级别的"通过"一律不接受。
2. **E0 不得升格**：读代码看到"有这条分支"不等于"能触发"（G1 闸门，三轮"码在路不通"的教训）。
3. **E1 不得升格为 E2/E3**：进程内通过不能证明传输层、鉴权、持久化、并发。
4. **E2 不得升格为 E3**：隔离环境全绿不能证明生产。
5. **BLOCKED 项即使 E2 全绿，结论只能是"生产未验收（E2 通过 / E3 BLOCKED）"，不得写"验收通过"**，也不得因 Mock 通过而修改本文件头部的「状态」行。

**当前可得上限**：`2c48579` 尚无对应 Mock 实现 → 全部用例目前最高 **E0**；`e7be8c9` 的历史探针属 **E1**，且只对旧契约有效，不得迁移。

### 6.2 写入次数：四层口径（本轮第 6 项）

> 队长要求区分「`changes.length` 算出的预期写入数」「`applied_changes` 回执」「实际持久化证据」。落为四层，必须全等。

| 层 | 名称 | 取值来源 | 典型陷阱 |
|---|---|---|---|
| **W1** | 声明值 | `len(changes)` | 声明数 ≠ 生效数（同 target 重复、同键已存在） |
| **W2** | 预期值 | 按持久化目标去重后的数量 | `schedule_one_time` 每 task 最多 1 条、`upsert_daily_override` 每 `(item_type,item_id,local_date)` 最多 1 条；**W1 > W2 本身即缺陷** |
| **W3** | 回执值 | `len(applied_changes)` | 回执可虚报：`e7be8c9` 的 F3 就是回读失败仍 `readback_verified=true` |
| **W4** | 持久化值 | 逐目标直接查库：该行是否新增 / 字段是否变更 | **不能用 `count(*)` 差**：更新不改行数 |

**判定**：

- `W1 = W2 = W3 = W4` 才 PASS。本文件每条用例的"预期写入次数"一律指 **W4**，W1–W3 作佐证列。
- `W3 < W4` → **静默多写**（最严重，用户看不到）。
- `W3 > W4` → **回执虚报**（界面显示"已安排"但库未变）。
- `W4` 必须附**主键稳定性**与**字段指纹**：`count(*)` 差为 0 但 `override_id` 从 `ov_0038` 变成 `ov_0063`，仍算 1 次写入且属语义错误（T09-c 的实测形态）。
- 三路以上不一致时**以 W4 为准**记录，并把差异写进备注，不得取平均或"多数一致"。

### 6.3 响应码

以实际 HTTP 状态 + `error.code` **双重记录**，两者不一致视为契约缺陷（F1）。`details` 中的 `proposal_id`、`approval_status` 也要抄录——`2c48579` 的 `readback_pending` 只出现在 `details` 里。

### 6.4 失败归因三类（不得混为一谈）

- **F1 契约缺陷**：契约未定义或自相矛盾，用例无法判定 → 提交 M0（如 B16、B18、B19）
- **F2 实现缺陷**：契约明确但实现不符 → 提缺陷单
- **F3 夹具缺陷**：前置数据或故障注入不成立 → 修用例，不计入实现质量

### 6.5 回填规则

只有在真实执行后，才允许在本文件追加"实测"列；执行依据须注明**环境（E0–E3）+ 时间 + SHA**。当前环境为 **BLOCKED**，故严格执行"零实测记录"。

### 6.6 本轮 4 个 BLOCKED 硬边界

`base_version` 生成与事务内比较、可信审批与 Token 签名/TTL、原子写入与幂等存储、生产回读——这 4 项仍未实现。**任何用例只要判定依赖其中之一，最高只能给 E2**；契约里写明了不等于已具备，Mock 通过也不等于生产可用。

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
| 2026-11-01 | **第三轮增量对齐到 `c53b1a9`**：基准换 SHA；§3C 改判表（9 条升可判 + R1/G1/S1 口径更新）；新增 V1/Y1；§5 的 B5–B18 全部结算解除、B19 收窄（G5 残留）；统计 30/31 → **32/33（32 可判 / 1 部分 / 0 不可判）** | 对应队长邮件 7 项；零执行，全部 E0；EX-17 改判可执行见 §3C.1 |
| 2026-10-30 | 初版，定义 T01–T12 预期 | 仅预期，未执行；待 M0 修订状态机与错误码后复核 |
| 2026-10-30 | 追加 T15 条件式占位（单日 skip，分支 A/B）；新增 B10；补 §4.1 PR #3 评审增量 | T15 在 skip 语义定稿前不可执行；无实测记录 |
| 2026-10-31 | 新增 T04-b、T12-b、T16 | 对应 A 侧 10-31 九项修订，判据见 `docs/reviews/2026-10-31-a-fix-verification-checklist-M3.md` |
| 2026-10-31 | 新增 T17（过期审批重建）；新增 §7 Mock 实测记录 | 在 e7be8c9 上实测：T08/T04-b/T09-b 通过，T16/T17 失败，明细见 recheck 文档 |
| 2026-10-31 | 新增 §2 状态机与用例映射、T18（APPROVAL_CONSUMED 可达性）、§4.1 八项索引；T09 回读字段扩至 7 项；章节重排 | 仅定义预期与可达性，无新增实测；按队长要求保留 8 项重点 |
| 2026-10-31 | 依 M0 再次确认的固定 SHA 复核两份契约文件：加入 Git blob / SHA-256 指纹与机检结果（20 示例、8 错误响应、8/20 码覆盖、0 结构缺失）；新增 B17（`approval_status` 同名双域） | 机检可复算，非实测；误报项已复核并说明 |
| 2026-10-31 | **M0-1 固定基准增量对齐**：头部固定 SHA 与 PR；T03 拆为 T03-a（`READBACK_MISMATCH`，终态待定）/ T03-b（`READBACK_PENDING`，同键只回读）；新增 B16；B11 补"消费时点"缺失；统计改 22 编号 / 23 用例项（16/4/3） | 未改契约本体、未重跑实测；只做 C 侧用例口径对齐，明细见 `docs/reviews/2026-10-31-c-incremental-alignment-2c48579.md` |
| 2026-10-31 | **按 `2c48579` 最终稿全量重判**：§2.1/2.2 状态迁移改判（6 闭合/2 部分）、§2.3 错误码表扩至 20 个、T12-b 枚举修正、T15 改为负向用例、新增 T19–T22、§5 阻塞结算（B1–B4/B8/B10 闭合，新增 B11–B15）、§7 注明新契约无 Mock、§9 标注已执行 | **纯文档级复审，无任何实测**；结论见 `docs/reviews/2026-10-31-m0-final-2c48579-incremental-M3.md` |
| 2026-10-31 | 新增 §4.2：声明任务拆解质量（DA01–DA15）**不属于本矩阵**，契约无拆解工具；判据另立 `docs/contest/decomposition-acceptance.md` | 对应计划 D3 的 C 侧任务；DA 系列零执行，不新增任何实测 |
| 2026-10-31 | 按队长第二次指示补 **B19 语义验收**：新增 G3（`=null` 用完整目标）/ G4（「无需安排」与「排不下」隔离）/ G5（20 < 最小块长）；G1–G5 五种预算值组成对照；统计改 30 编号 / 31 项（21/7/3）；B19 解除条件补第三句 | **仍零实测**；G3 为唯一完全由契约明文支撑的一条 |
| 2026-10-31 | **按队长 6 项增量追加 §3B**：R1（Token 过期后重建须换 `approval_id`、旧 Token 永久失效）、X1（非终态换新幂等键 → `READBACK_PENDING`、零写入）、G1（`remaining_minutes_today=0` 不成块且不入 `unplanned_tasks`）、G2（=40 只排 40 分钟）、S1（只认服务端完整 Schema，不认 M2 DTO）；§6 重写为 **E0–E3 四级证据** + **W1–W4 四层写入次数**；新增 B18（P0，契约真空）/ B19（P1）；§2.1/§2.2 各补 1 行映射；统计改 27 编号 / 28 项 | **只增量追加，未重审旧问题、未改契约本体、无新增实测**；B18 是首条"契约真空必写两次"的 P0 |

## 9. 单次增量复审清单（`2c48579`、`c53b1a9` 各执行一次）

> 2026-11-01 第二次执行：按本清单对 `c53b1a9` 完成 §3C 全部改判与 §5 结算；A/M1 需按新基准重做 Mock 后，方可按 §3B/§3C 判据跑首轮真实执行。

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
