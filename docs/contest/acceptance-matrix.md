# M0 Agent API v1 验收矩阵（T01–T16）

- **归属**：M3 / Evaluation（同学 C）
- **对象**：`docs/contracts/agent-api-v1.md` @ `503210c`（v1 CANDIDATE）
- **状态**：**预期定义阶段，尚未执行任何一条**
- **纪律**：本文件只写"输入"与"预期"。所有预期列都是**待验证的断言**，不是实测结果。执行后再另开一节回填实测值，本文件在此之前不得被引用为"已通过"。
- **复核时点**：M0 修订状态机与错误码之后，逐条复核 §5「待 M0 定义」中的占位项。

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

## 2. 主矩阵

### T01 写后回读不可见 → 进入 readback_pending

- **输入**：apply `{proposal_id, base_version, approval_token, idempotency_key=K1}`；故障注入：写入链路成功提交，但回读路径返回空（模拟 RLS 生效延迟）
- **预期响应码**：`READBACK_MISMATCH`（502）
- **预期 Proposal 状态**：**`[待定]`** —— 契约 §5.7 无此状态；按 P0-1 建议应为 `readback_pending`
- **预期数据结果**：库中已有 1 条变更（可能已提交），但响应**不得**声称成功、不得回填 `applied_changes`
- **预期写入次数**：**1**（第一次写入发生且只发生一次）
- **判定要点**：`READBACK_MISMATCH` 与「写入真的失败了」不可混淆；见 §4 阻塞项 B1

### T02 同键重试，回读恢复

- **输入**：T01 之后，用**同一** `idempotency_key=K1` 再次 apply（回读此时可见）
- **预期响应码**：`success`
- **预期 Proposal 状态**：`applied`
- **预期数据结果**：`readback_verified=true`；`applied_changes` 与 T01 实际落库内容一致；无新增行
- **预期写入次数**：**累计仍为 1**（重试只做回读，不得二次写入）
- **判定要点**：这是幂等能力的核心断言。写入次数若变 2，本用例直接 FAIL

### T03 回读持续不一致 → 终局

- **输入**：T01 之后同键重试 N 次（N 由 M0 定义，建议 3），回读始终不一致
- **预期响应码**：**`[待定]`** —— 契约未定义终局错误码；建议沿用 `READBACK_MISMATCH` 但附终局标记，或新增 `READBACK_UNRESOLVED`
- **预期 Proposal 状态**：**`[待定]`** —— 建议 `failed`，需与"写入明确失败"的 `failed` 可区分
- **预期数据结果**：不得自动回滚（契约未授权回滚）；应留下可审计的终局记录供人工复核
- **预期写入次数**：**仍为 1**
- **判定要点**：本用例当前**不可判**，依赖 M0 定义终局语义；见 §4 阻塞项 B1

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
- **预期数据结果**：`duration_source` 依次为 `task_target` / `snapshot_estimate` / `fallback`；block 的 `end_at` 随之变化，但**库中仍无结束时间列**，回读只校验 `planned_date` + `scheduled_at`
- **预期写入次数**：各 **1**
- **判定要点**：优先级必须是任务自身 > 快照估算 > 兜底。`duration_source` 若恒为同一值，说明未真正分档，判 F2 实现缺陷。本用例不得被误读为"`end_at` 要写入数据库"——T12 的反向断言仍然生效

### T15 单日 skip（条件式占位，待 M0 定义 skip 语义）

> 状态：**条件式占位**。契约 open question 5 提出的单日 `skip` 尚未定义，本用例按两种可能语义分别给出预期，M0 定稿后删除不适用的分支并去掉本标注。**在语义定稿前此用例不可执行。**

- **输入**：对重复任务 `T_RE_1`（每日规则）在 `2026-11-04` 发起单日 skip，生成 Proposal 并 apply
- **分支 A：skip 仅作用于当天**（与现有 `DailyItemOverride(action: skip)` 语义对齐，`app_database.dart` 单日例外表）
  - **预期响应码**：`success`
  - **预期 Proposal 状态**：`applied`
  - **预期数据结果**：2026-11-04 该任务**不产生 occurrence**；库中仅新增一条 `action=skip` 的单日例外；**2026-11-05 及之后日期的 occurrence 不受影响**；长期规则行零变更
  - **预期写入次数**：**1**（仅例外表）
- **分支 B：skip 连带后续日期**（若 M0 定义为"顺延"语义）
  - **预期数据结果**：当天不产生 occurrence，且后续日期按顺延规则偏移；此分支需 M0 给出顺延终止条件（如 `skip_count` 上限）
  - **预期写入次数**：1（若顺延展开为逐日例外，则写入次数 = 顺延天数，需 M0 明确）
- **共同断言（两分支均适用）**：skip 不得修改任务的长期重复规则；对同一 `(user, item, date)` 重复 skip 两条不同 `override_id` 的提案，第二次 apply 的行为必须与 T09-a 的唯一键口径一致
- **判定要点**：真实代码已有 `action=skip` 例外类型（`today_page.dart` 范例），但契约未定义其错误语义与幂等口径；若 M0 选择分支 A，本用例可直接复用 T09 的三路取证方式

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

---

## 3. 覆盖对照（队长点名的 7 个重点）

| 重点 | 覆盖用例 | 当前可判性 |
|---|---|---|
| `readback_pending` | T01、T02、T03 | 部分不可判——状态位与终局未定义（P0-1） |
| 版本冲突 | T04 | 可判（需 §6.5 补错误码绑定，P0-2） |
| 并发 apply | T07 | 部分不可判——执行中响应未定义（P1-9） |
| 重复 apply | T08 | 不可判——错误码缺失（P0-4） |
| override 唯一键冲突 | T09-a/b/c | T09-a/b 不可判——缺必填校验与策略（P0-2 相关） |
| available_from / deadline | T10-a/b | 部分可判——`violations[].code` 未定义（P1-8） |
| `end_at` 不参与持久化验收 | T12 | **可判**（契约 §5.6 表述清晰） |
| 单日 skip（新增，open question 5） | T15 | **不可执行**——skip 语义未定义，分支 A/B 待 M0 二选一 |
| A 侧 10-31 修订（9 项待处理） | T04-b（摘要重算）、T08（判定顺序）、T12-b（时长来源）、T05/T06（过期）、T09-b（NOT_FOUND）、T16（审批第三态）、T10（夹具正规化） | 判据已备，等 A 新固定 HEAD；逐项判据见 `docs/reviews/2026-10-31-a-fix-verification-checklist-M3.md` |

另附两条非重点但成本低的用例：T13 请求体携带 `user_id` → `INVALID_ARGUMENT`；T14 空任务/空日历 → `success` + 空数组（不得 404）。

---

## 4. 阻塞与待 M0 定义

| 编号 | 待定义项 | 影响用例 | 解除条件 |
|---|---|---|---|
| B1 | `readback_pending` 状态位与终局判定 | T01、T02、T03 | §5.7 状态枚举增加 `applying`/`readback_pending`，或 apply 响应增加 `idempotency_state` |
| B2 | apply 阶段版本冲突的错误码绑定 | T04 | §6.5 显式写明返回 `SNAPSHOT_CONFLICT` 且 token 失效 |
| B3 | 提案过期错误码 | T06 | 新增 `PROPOSAL_EXPIRED` 或明确复用 `APPROVAL_EXPIRED` |
| B4 | 已应用提案的重复 apply 错误码 | T08 | 新增 `PROPOSAL_ALREADY_APPLIED`，并规定检查顺序 |
| B5 | `violations[].code` 枚举 | T10、T11 | 定义封闭枚举与 `details` schema |
| B6 | 幂等"执行中"响应 | T07 | 明确 409+`in_progress` 或 202 |
| B7 | `FORBIDDEN` / `NOT_FOUND` 策略 | T09-b | 按资源类型给出默认策略 |
| B8 | `approval_token` 一次性还是可重放 | T05（衍生 T07） | 二选一，两者安全测试不同 |
| B9 | 真实服务可用性 | 全部 | 快照服务、审批、原子写入、远程 API 仍 BLOCKED |
| B10 | 单日 skip 语义（仅当天 / 顺延后续） | T15 | 契约 open question 5 定稿：选定分支 A 或 B，并给出顺延终止条件与写入口径 |

### 4.1 来自 PR #3 评审（@bbf0992）的增量阻塞与解锁项

详见 `docs/reviews/2026-10-30-m1-pr3-review-M3.md`（本地暂存，是否入库待队长安排）：

- **解锁 T08**：PR #3 的 Mock 实现中 `ALREADY_APPLIED` 因判定顺序（状态检查先于已应用检查，`tool_server.py:527/:529`）不可达；M0 若按评审建议修正判定顺序并把 `PROPOSAL_ALREADY_APPLIED` 写入 §4.1，B4 解除。
- **新增错误码待入契约**：`APPROVAL_CONSUMED`、`ALREADY_APPLIED` 已在 Mock 实现中出现但不在契约 §4.1 的 14 码表内，与 B4 同批处理。
- **T09-b 假通过风险**：Mock 的 `upsert_daily_override` 不校验 item 存在性，且 daily_override 变更缺回读核验（契约 §5.6 要求）；在真实服务接入前，T09-b 与 T12 类回读断言在 Mock 上**不得记为 PASS**。
- **B8 收窄**：PR #3 已实现"外部确认后才签发 + 一次性 token"，方向与评审建议一致；但 token 无签名无 TTL、审批存储无访问控制，B8 仍不能视为解除。

在 B1–B8 未定之前，矩阵中相关单元格保持 `[待定]`，**不替 M0 填默认值**，也不以 Mock 结果代替真实结论。

---

## 5. 执行与取证规则（留给后续执行时使用）

1. **写入次数**必须三路取证并一致：目标表行数差、幂等记录的执行计数、服务端应用日志的写入次数。三者不一致时以行数为准并记录差异。
2. **响应码**以实际 HTTP 状态 + `error.code` 双重记录，两者不一致视为契约缺陷（F1）。
3. 失败分三类归因，不得混为一谈：
   - **F1 契约缺陷**：契约未定义或自相矛盾，用例无法判定 → 提交 M0
   - **F2 实现缺陷**：契约明确但实现不符 → 提缺陷单
   - **F3 夹具缺陷**：前置数据或故障注入不成立 → 修用例，不计入实现质量
4. 只有在真实执行后，才允许在本文件追加"实测"列；执行依据须注明环境（Mock / 真实服务）与时间。当前环境为 **BLOCKED**，故严格执行"零实测记录"。

---

## 6. 变更记录

| 日期 | 变更 | 说明 |
|---|---|---|
| 2026-10-30 | 初版，定义 T01–T12 预期 | 仅预期，未执行；待 M0 修订状态机与错误码后复核 |
| 2026-10-30 | 追加 T15 条件式占位（单日 skip，分支 A/B）；新增 B10；补 §4.1 PR #3 评审增量 | T15 在 skip 语义定稿前不可执行；无实测记录 |
| 2026-10-31 | 新增 T04-b（validate 摘要重算）、T12-b（时长来源优先级）、T16（审批第三态与重复 request 幂等） | 对应 A 侧 10-31 九项修订，判据见 `docs/reviews/2026-10-31-a-fix-verification-checklist-M3.md`；仍无实测记录 |
