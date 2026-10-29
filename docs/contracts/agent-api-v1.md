# CheckD Agent API v1 契约

状态：**v1 CANDIDATE / 待 M0、M1、M2、M3 共同评审，尚未冻结**  
契约版本：`checkd.agent.v1`  
业务时区：`Asia/Shanghai`

> 本文定义拟建的 Agent 工具协议，不代表仓库中已经存在远程服务器、
> WorkBuddy 工具、审批服务或可用的生产 API。当前可确认的能力、拟建能力和
> BLOCKED 项在文末分别列出。

## 1. 目标与非目标

v1 定义五个拟建工具：

1. `list_tasks`
2. `get_calendar_events`
3. `generate_schedule`
4. `validate_schedule`
5. `apply_approved_changes`

v1 只负责读取任务和日历、生成并校验调度提案，以及在可信审批后写入允许的
计划变更。它不创建或修改 TimerSession、完成记录、统计事实、周期规则、课程
长期规则或用户身份。

`ScheduleBlock` 仅为调度提案中的 DTO。当前仓库没有 ScheduleBlock 数据表或
Repository。一个单次事项当前只能持久化一个计划日期，以及可选的一个具体计划
时间；v1 不声称支持把同一单次事项持久化成多个未来时间块。

## 2. 已核实的代码语义

| 语义 | 代码证据 | 契约结论 |
|---|---|---|
| 周期任务与单次事项 | `TaskKind.recurring/oneTime`、`TaskDetails` | API 使用 `recurring` / `one_time` |
| 日期型与精确截止 | `TaskDeadline.dateOnly/exact` | 使用带判别字段的 `deadline`，禁止把日期型截止转换成 23:59 |
| 单次事项计划 | `plannedDate`、`scheduledAt`、`effectivePlannedDate` | 至多一个计划日期；`scheduled_at` 存在时必须与 `planned_date` 同日 |
| 周期规则 | `TaskScheduleRule`、`WeekdayMask` | 星期为 ISO 1–7；起止日期是本地日历日期 |
| 课程规则 | `CourseScheduleRule`、`CourseWeekRuleType` | 课程与 Task 分离；固定课程不得被调度器移动 |
| 日历聚合 | `buildCalendarOccurrencesForDate` | Course、Task、单日例外合成有效日历事件 |
| 单日例外 | `DailyItemOverride`、`DayScheduleRepository.saveDailyOverride` | 只影响 `local_date` 指定日期，不改长期规则 |
| 用户隔离 | 各 Repository 使用构造时的 `_userId`；`SyncRemoteReader.readTable(... userId)` | 外部服务必须从已验证凭证确定用户，不能信任请求体 userId |
| 同步边界 | Drift Repository + SyncQueue；Supabase 下载按表恢复 | 绕过 Repository 的云端写入能否安全收敛仍需证明 |

实际仓库路径中，单日例外仓库位于
`lib/features/schedule/data/day_schedule_repository.dart`，不是 `domain/`。

## 3. 时间、标识和 JSON 规则

- 所有字段使用 `snake_case`。
- `api_version` 固定为 `checkd.agent.v1`。
- 业务时区固定为 `Asia/Shanghai`。v1 不接受其他业务时区。
- `dateOnly` 使用 `YYYY-MM-DD`，表示上海本地日历日期，不是 UTC 时间点。
- 精确时间必须是 RFC 3339 / ISO 8601 字符串，并带明确偏移，例如
  `2026-10-30T14:00:00+08:00`。禁止无偏移时间。
- 分钟字段为当天从 `00:00` 起算的整数；开始分钟范围 `0..1439`，结束分钟
  范围 `1..1440`，并且结束必须晚于开始。
- 星期使用 ISO 8601：周一为 `1`，周日为 `7`。
- 所有 ID 都是不透明字符串。调用方不得从 ID 推断用户或数据表。
- 所有 Mock ID、追踪 ID、审批字符串均为不可用于生产的虚构值。

### 3.1 截止日期联合类型

日期型截止：

```json
{"kind":"date_only","date":"2026-11-02"}
```

精确截止：

```json
{"kind":"exact","at":"2026-11-02T18:00:00+08:00"}
```

`kind=date_only` 时只能出现 `date`；`kind=exact` 时只能出现 `at`。

## 4. 通用请求与响应

身份凭证必须通过实际工具通道或 HTTPS Authorization 元数据传递，并由服务端
验证。请求 JSON **没有 `user_id` 字段**。若调用方发送 `user_id`，服务端应以
`INVALID_ARGUMENT` 拒绝，避免产生“请求体指定身份”的错觉。

通用请求字段：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `api_version` | string | 是 | 固定 `checkd.agent.v1` |
| `request_id` | string | 是 | 调用方生成的单次请求标识；1–128 字符，不含密钥 |
| `timezone` | string | 是 | 固定 `Asia/Shanghai` |
| `input` | object | 是 | 工具专属输入 |

成功响应：

```json
{
  "api_version": "checkd.agent.v1",
  "request_id": "req_mock_001",
  "trace_id": "trace_mock_001",
  "status": "success",
  "data": {}
}
```

失败响应：

```json
{
  "api_version": "checkd.agent.v1",
  "request_id": "req_mock_001",
  "trace_id": "trace_mock_001",
  "status": "error",
  "error": {
    "code": "INVALID_ARGUMENT",
    "message": "请求参数无效。",
    "retryable": false,
    "details": [{"field":"input.date_range.start","reason":"invalid_date"}]
  }
}
```

`trace_id` 由服务端产生，用于关联日志；不得包含 token、任务内容或用户身份。
错误 `message` 必须安全、可展示，不回显原始 payload、数据库语句或凭证。

### 4.1 统一错误代码

| code | HTTP 建议 | 含义 |
|---|---:|---|
| `AUTH_REQUIRED` | 401 | 缺少、过期或无法验证的身份凭证 |
| `FORBIDDEN` | 403 | 已认证但无权访问目标资源 |
| `INVALID_ARGUMENT` | 400 | 字段、日期、时区或联合类型无效 |
| `NOT_FOUND` | 404 | 已授权范围内找不到资源 |
| `DEPENDENCY_UNAVAILABLE` | 503 | 读取、调度或持久化依赖不可用 |
| `PROPOSAL_INVALID` | 422 | Proposal JSON 结构、类型、未知字段或 change 类型无效 |
| `SNAPSHOT_CONFLICT` | 409 | 当前可信版本与提案 `base_version` 不一致 |
| `APPROVAL_REQUIRED` | 403 | 尚无可验证审批 |
| `APPROVAL_EXPIRED` | 403 | 审批已过期 |
| `APPROVAL_UNTRUSTED` | 403 | 审批签名、主体或提案绑定无效 |
| `IDEMPOTENCY_CONFLICT` | 409 | 相同幂等键被用于不同请求 |
| `WRITE_BLOCKED` | 503 | 原子写入、RLS、同步收敛或审批链尚未实证 |
| `READBACK_MISMATCH` | 502 | 写后回读与批准内容不一致；不得返回成功 |
| `INTERNAL_ERROR` | 500 | 已脱敏的未知服务错误 |

## 5. 共享 DTO

### 5.1 `date_range`

```json
{"start":"2026-10-29","end":"2026-11-04"}
```

包含首尾日期，必须满足 `start <= end`。v1 建议最多 31 天；实际限额由服务实现
并在部署文档中固定，未固定前超过 31 天一律拒绝。

### 5.2 `task`

公共字段：

- `task_id`：不透明任务 ID。
- `kind`：`recurring` 或 `one_time`。
- `name`：非空名称。
- `status`：`active`、`paused` 或 `archived`。
- `execution_mode`：`timed` 或 `untimed`；只描述任务配置，不是计时状态。
- `available_from`：可空 `dateOnly`，仅适用于单次事项。
- `planned_date`：可空 `dateOnly`，单次事项唯一计划日期。
- `scheduled_at`：可空带偏移 instant，单次事项唯一具体计划时间。
- `deadline`：可空的截止联合类型。
- `duration_target_seconds`：可空正整数。
- `updated_at`：带偏移 instant，仅用于展示/映射，不替代可信快照版本。

周期任务另含 `recurrence`：

- `preset`：`daily`、`weekdays`、`weekends` 或 `custom`。
- `weekdays`：排序且不重复的 ISO 星期数组。
- `starts_on` / `ends_on`：本地日期；`ends_on` 可空。
- `scheduled_minute_of_day`：可空，仅为长期规则当前默认计划分钟。

单次事项不得包含 `recurrence`。周期任务不得包含单次事项的
`available_from/planned_date/scheduled_at/deadline`。

### 5.3 `course` 与课程规则

Course 独立于 Task。课程包含 `course_id/name/status`、可空的学期日期和
`rules`。规则包含 `rule_id/weekday/week_rule_type/start_week/end_week/`
`interval_weeks/week_numbers/start_minute/end_minute`。`week_rule_type` 是
`every_week`、`odd_weeks`、`even_weeks`、`every_n_weeks` 或 `custom`。

课程规则属于固定约束。v1 调度和写入工具不得修改规则，也不得以单次事项形式
复制课程。

### 5.4 `calendar_event`

- `event_id`：不透明的有效日历事件 ID。
- `event_type`：`course`、`recurring_task`、`one_time_task` 或
  `external_fixed_event`。
- `source_id`：Course、Task 或外部固定事件 ID。
- `date`：本地日期。
- `start_at` / `end_at`：有时间事件使用带偏移 instant；无时间 Task 可为 null。
- `fixed`：课程和突发会议为 `true`；不可被调度移动。
- `applied_override_id`：可空；表示该日有效时间来自单日例外。

`list_tasks` 返回去重的 Task 定义：同一 `task_id` 在一个响应中最多出现一次。
逐日是否发生、当天生效时间以及单日例外后的结果由
`get_calendar_events.events` 表达；周期任务不能因为查询跨多天而重复返回多份
Task 定义。

### 5.5 `daily_override`

- `override_id`、`item_type`、`item_id`、`local_date`、`action`。
- `item_type` 对应现有 `recurring`、`one_time`、`course`。
- 可能包含 `planned_start_minute`、`planned_end_minute`。
- 只作用于 `local_date`。读取时可以返回课程例外；v1 Agent 写入不允许修改课程。

### 5.6 `schedule_block`（仅提案 DTO）

- `block_id`：提案内部 ID，不是数据库 ID。
- `task_id`：关联一个 Task。
- `task_kind`：`recurring` 或 `one_time`。
- `start_at` / `end_at`：带 `+08:00` 等明确偏移的 instant。
- `source`：固定为 `proposal`。
- `persistable_as`：`one_time_schedule` 或 `daily_override`。
- `duration_source`：`task_target` 或 `scheduler_estimate`。
- `duration_seconds`：`end_at - start_at`，正整数。

同一单次事项在一个提案中最多出现一个可持久化 block。需要拆解的大任务应由
上游先产生多个独立 Task；v1 不把一个 Task 的多个 block 假装成现有能力。

`start_at` 和 `end_at` 都是建议展示值，但持久化能力不同：

- 对 `schedule_one_time`，现有模型只持久化 `planned_date` 和可选的
  `scheduled_at`。它只将 block 的 `start_at` 映射为计划开始时间；`end_at`、
  `duration_seconds` 和 `duration_source` 不属于该操作的持久化字段，也不属于
  写后回读的成功断言。
- 对没有实际 `duration_target_seconds` 的 Task，调度器可以给出
  `duration_source=scheduler_estimate` 的明确估算，但不得把估算写回或描述为现有
  Task 的持久化时长。
- 对 `upsert_daily_override`，开始和结束分钟都能映射到现有单日例外；仍须按
  change 白名单回读验证。

### 5.7 `schedule_proposal`

- `proposal_id`：服务端生成的不透明 ID。
- `snapshot_ref`：服务端创建并保存的 Agent 调度快照引用；客户端和模型不得构造。
- `base_version`：与 `snapshot_ref` 绑定、由可信服务产生的版本标识。
- `input_digest`：服务端对规范化调度输入生成的摘要，覆盖 Task、有效日历事件、
  单日例外、偏好以及外部固定事件；客户端提供的摘要不可信。
- `status`：`draft`、`validated`、`pending_approval`、`applied`、`rejected`、
  `expired` 或 `failed`。
- `expires_at`：带偏移 instant。
- `blocks`：提案展示块。
- `changes`：允许持久化的变更。
- `unplanned_tasks`：无法安排的 Task 及原因。
- `explanations`：面向用户的脱敏解释数组。

状态机固定为：

```text
draft → validated → pending_approval → applied
                               ├────→ rejected
                               ├────→ expired
                               └────→ failed
```

结构合法但硬约束校验失败时 Proposal 保持 `draft`，通过修改输入重新生成，而不是
伪造 `validated`。`failed` 表示服务执行失败，不代表写入一定未发生；具体是否可
重试仍由幂等记录和回读状态决定。

允许的 `changes` 只有：

1. `schedule_one_time`：设置单次事项的唯一 `planned_date`，并可设置同日的
   `scheduled_at`。
2. `upsert_daily_override`：为一个 `recurring` 或 `one_time` Task 在单个
   `local_date` 写入 `reschedule` 例外及分钟范围。

两种 change 的字段固定如下：

| type | 必填字段 | 可选字段 | 额外约束 |
|---|---|---|---|
| `schedule_one_time` | `change_id`、`type`、`task_id`、`planned_date` | `scheduled_at` | Task 必须是 `one_time`；具体时间必须与计划日期同日；一个提案中同一 Task 最多一条 |
| `upsert_daily_override` | `change_id`、`type`、`item_type`、`item_id`、`local_date`、`action`、`planned_start_minute`、`planned_end_minute` | `existing_override_id` | `item_type` 仅 `recurring`/`one_time`；`action` 在 v1 暂定仅 `reschedule`；结束分钟必须晚于开始分钟 |

`change_id` 是提案内的稳定标识，不是数据库 ID。`existing_override_id` 只能由
可信读取服务提供；模型不得猜测。服务端必须拒绝未列出的字段和 change 类型。

远程服务执行单日例外时还必须验证：`item_id` 属于当前已认证用户、资源真实
存在、`item_type` 与实际资源类型一致、`existing_override_id`（若有）属于同一
用户，以及 action 位于 v1 白名单。现有 Repository 的参数校验不能替代这些
远程权限检查。

禁止的 change：修改 Course 规则、修改周期任务长期 recurrence、创建或修改
TimerSession、修改完成记录、修改统计、写入多个单次事项未来块。

## 6. 工具契约

### 6.1 `list_tasks`

**用途：** 在已认证用户范围内读取用于展示或调度的任务。

请求 `input`：

- `date_range`：必填。
- `kinds`：可选数组，值为 `recurring` / `one_time`。
- `statuses`：可选数组，默认仅 `active`。
- `include_completed`：可选布尔值，默认 `false`。

成功 `data`：

- `query_version`：仅标识这一次普通读取结果的服务端版本；不能作为
  `generate_schedule.base_version`，也不保证与另一工具响应一致。
- `tasks`：Task DTO 数组。
- `date_range`：实际查询范围。

`tasks` 是范围内可供展示/调度的去重 Task 定义，而不是每天一份 occurrence。
校验和失败：固定时区、合法范围、枚举不重复；无数据返回空数组而不是 404。
身份来自服务端凭证。依赖拟建只读适配、TaskRepository/云端表映射和经验证 RLS。

### 6.2 `get_calendar_events`

**用途：** 返回给定范围内生效的课程、任务和单日例外结果，并接受仅在当前
调度请求中使用的外部固定事件，例如突发会议。

请求 `input`：

- `date_range`：必填。
- `external_fixed_events`：可选数组；每项必须有 `external_event_id/title/`
  `start_at/end_at`，并满足结束晚于开始且落在范围内。

成功 `data`：

- `query_version`：仅标识本次普通日历读取；不承诺与 `list_tasks` 的
  `query_version` 相同，也不能直接作为 Proposal 的 `base_version`。
- `courses`：Course DTO 数组。
- `daily_overrides`：单日例外数组。
- `events`：有效事件数组，包括外部固定事件。

`events` 是逐日 occurrence：同一周期 Task 或 Course 可以在不同日期出现多次。
外部事件只参与本次查询/提案，不写入 CheckD。空日历返回三个空数组。

`list_tasks` 与 `get_calendar_events` 是普通独立查询。两个响应即使时间接近，也
不自动组成一致快照。当前 Supabase/Drift 同步代码不提供 Agent 专用统一快照服务。

### 6.3 `generate_schedule`

**用途：** 由 M2 的确定性调度器基于快照生成提案，不执行写入。

请求 `input`：

- `date_range`：必填。
- `external_fixed_events`：可选；结构与 `get_calendar_events` 相同。
- `preferences`：可选，例如 `day_start_minute/day_end_minute/`
  `minimum_block_minutes`；不得覆盖硬约束。

远程工具请求**不接受** LLM 提交的 `tasks/courses/calendar_events/`
`daily_overrides/base_version/snapshot_ref`。远程服务包装层必须根据已验证用户、
日期范围和外部事件创建服务端快照，规范化为 M2 DTO，再调用纯调度函数。

M2 的进程内纯函数仍可直接接收 Task/Course/Event/Override DTO，以便确定性单元
测试；这是内部接口，不等于远程工具可以信任这些 DTO。

成功 `data`：完整 `schedule_proposal`，含服务端产生的 `snapshot_ref`、
`base_version` 和 `input_digest`。生成器必须保留固定课程和会议，区分
日期型与精确截止，并将无法安排项放入 `unplanned_tasks`。它不能自行生成一个
版本，也不能接受客户端提供的“看起来合法”的版本或快照引用。

可信快照存储、`base_version` 生成与验证尚未实现，因此远程工具真实实现保持
**BLOCKED**。现有 Supabase 或 Drift 不得被描述为已经提供该能力。

### 6.4 `validate_schedule`

**用途：** 服务端针对当前可信快照重新校验提案。只校验，不写入，也不自行
代表用户批准。

请求 `input`：

- `proposal_id`：必填。服务端必须加载自己保存的 Proposal 和快照绑定；不接受
  调用方重新提交完整 Proposal 作为可信输入。

成功 `data`：

- `proposal_id`、`snapshot_ref`、`base_version`、`input_digest`。
- `proposal_status`：合法提案进入 `pending_approval`；约束失败时保持 `draft`。
- `validation_status`：`valid` 或 `invalid`。
- `approval_status`：合法提案为 `pending_approval`；约束失败为
  `not_approvable`。
- `violations`：结构化约束错误数组。
- `validated_at`、`expires_at`：带偏移 instant。

结构/类型/未知字段错误返回 `PROPOSAL_INVALID`。结构合法但违反调度硬约束时返回
成功响应、`validation_status=invalid` 和结构化 `violations`，Proposal 保持
`draft` 且不能审批。

必须检查：身份所有权、版本、输入摘要、时间格式、截止语义、固定事件冲突、同一单次事项
最多一个 block、change 白名单、单日例外日期、Task/Course 存在性。版本不一致
返回 `SNAPSHOT_CONFLICT`。`valid` 不等于已批准。

### 6.5 `apply_approved_changes`

**用途：** 仅在可信用户确认已被转换成服务端可验证批准状态后，原子地应用
批准的白名单变更并回读核验。

请求 `input`：

- `proposal_id`：必填。
- `base_version`：必填；必须与已验证、已批准提案及 `snapshot_ref` 绑定。
- `approval_token`：必填；不透明、短期、一次性或可安全重放的服务端签名凭据。
- `idempotency_key`：必填；调用方生成，1–128 字符，不能包含用户数据。

服务端必须从审批存储加载原提案，不能接受请求体重新提交 `changes`。必须核验：

- 凭证主体与当前已认证用户相同。
- 凭证绑定完全相同的 `proposal_id`、`base_version` 和变更摘要。
- 凭证未过期、未撤销。
- 当前快照仍等于 `base_version`。
- 幂等键首次使用，或与完全相同请求重复使用。
- 所有变更在同一原子边界成功；无法证明原子性时返回 `WRITE_BLOCKED`。

成功 `data`：

- `proposal_id`、`base_version`、`result_version`。
- `idempotency_key`。
- `applied_changes`：实际持久化 ID 和规范化后的日期/时间。
- `readback_verified`：必须为 `true`。
- `applied_at`。

`schedule_one_time` 的回读只核验 `planned_date` 和可选 `scheduled_at`；不得用
提案 block 的 `end_at` 作为现有模型的持久化断言。

写后必须通过授权读取路径回读。任何缺失或不一致返回
`READBACK_MISMATCH`，不得返回成功。若写入可能已提交但回读失败，服务端必须把
幂等记录标为 `readback_pending` 或等价的不确定状态；同一幂等键重试只能重新
回读/核验，不能再次写入。

幂等作用域固定为 `authenticated_user_id + tool_name + idempotency_key`。服务端对
规范化的 `proposal_id/base_version/approval_grant_id` 生成请求摘要：

- 同一作用域、同一摘要：并发请求共享同一执行结果；后续请求返回原结果或继续
  安全回读，不重复写入。
- 同一作用域、不同摘要：返回 `IDEMPOTENCY_CONFLICT`。
- Proposal 还必须具备“最多成功应用一次”的唯一约束，换一个幂等键也不能再次
  应用同一 Proposal。

幂等存储介质、并发锁、保留期和崩溃恢复尚未实现，继续标记 **BLOCKED**。

## 7. 审批、版本和并发安全

### 7.1 审批凭据：当前 BLOCKED

五个已约定工具中没有 `approve_schedule`。因此 v1 **不新增第六个接口**，也不
假定 WorkBuddy 的按钮、自然语言“确认”或 Workflow 节点天然可信。

预期安全模型是：可信交互层收到用户明确确认后，将确认事件发送给受控审批
服务；审批服务验证登录主体、提案摘要和有效期，持久化批准状态，并签发绑定
`user/proposal_id/snapshot_ref/base_version/input_digest/change_digest/expires_at`
的 `approval_token`。

但当前尚未确认：

1. WorkBuddy 是否提供带已验证用户身份、防重放且可传给工具的确认信号。
2. 谁托管审批服务和审批状态。
3. 确认事件通过五个工具之外的何种平台机制送达审批服务。

在这些问题解决前，`apply_approved_changes` 的真实实现与端到端写入保持
**BLOCKED**；演示只能停在 Mock 或 `pending_approval`，不得用模型文本冒充批准。

### 7.2 `base_version`：当前 BLOCKED

`snapshot_ref` 和 `base_version` 必须由可信服务根据同一用户的任务、课程、
规则、单日例外及相关更新时间/版本产生，并能在写入事务中再次验证。外部固定
事件和偏好由 `input_digest` 绑定。模型、客户端或 Mock 不能自行编造生产版本。

当前仓库没有已证实的跨表原子快照版本，也没有已证实的提案版本表。Supabase
直接写入与 Drift/SyncQueue 收敛、跨表事务、RLS 和写后回读的生产行为也未完成
验证。因此：

- 普通读取的 `query_version` 不是 `base_version`。
- Mock 中的快照引用、版本和摘要仅用于结构评审，不能用于真实写入。
- Task 2 可先实现只读展示，但不得宣称版本冲突防护完成。
- Task 3 在确定服务端事务和版本算法前保持 `WRITE_BLOCKED`。

## 8. 权限与数据最小化

- 服务端只使用已验证凭证得出的主体 ID查询数据。
- 所有目标 Task、Course、Override 和 Proposal 都要再次核验 owner。
- 对其他用户的资源统一返回安全的 `FORBIDDEN` 或不泄露存在性的 `NOT_FOUND`，
  最终策略由安全评审冻结。
- 日志只记录工具名、trace ID、安全错误码、耗时和表/阶段标识；不记录 token、
  任务名称、notes、完整 payload 或个人日历内容。
- Mock 必须使用虚构 ID、课程、任务和会议。

## 9. 现状、依赖与 BLOCKED 清单

### 已存在的本地代码能力

- Task/Course/Calendar/DailyOverride 的领域模型与本地 Repository。
- 单次事项唯一计划日期/具体时间的本地写入。
- 单日例外本地写入及 SyncQueue 入队。
- Supabase 分表读取和 Drift 恢复框架。

### 仅为拟建接口

- 本文五个远程工具及其服务端路由。
- M2 调度引擎和 Proposal 持久化。
- WorkBuddy Tool Mapping。
- 审批存储、版本服务、幂等存储、原子写入和回读端点。

### BLOCKED

- WorkBuddy 可用工具协议、可信用户确认信号和身份传递。
- HTTPS/平台托管服务的位置与部署方式。
- 可信跨表 `base_version` 算法与事务内比较。
- Agent 专用 `snapshot_ref` 存储、输入规范化和摘要算法。
- 审批凭据签发者、审批存储和确认事件通道。
- Supabase 线上 migration/RLS 状态、原子写入和 Drift 同步收敛。
- 生产写入与真实 Agent API 可用性。

## 10. Open Questions（共同评审）

1. **M0 + M1：** WorkBuddy 是否提供可验证用户身份和可信确认事件？具体字段、
   签名、有效期及防重放保证是什么？若没有，审批 UI/服务由谁托管？
2. **M0：** 五工具约束下，确认事件如何到达审批服务而不静默新增接口？是否由
   WorkBuddy Workflow 的受控平台动作完成，还是必须修改工具清单？
3. **M0 + M2：** `snapshot_ref/base_version` 覆盖哪些表，内部 DTO 如何规范化，
   如何在读取和写入事务内生成/比较？
4. **M0：** 写入应经过本地 Repository/SyncQueue 还是受控服务端事务？如何证明
   两条路径最终收敛且不会覆盖离线修改？
5. **M0 + M2：** v1 `upsert_daily_override` 是否只允许 `reschedule`，还是还允许
   `skip/retarget`？本文为最小权限暂定只允许 `reschedule`。
6. **M1 + M3：** 无可信审批能力时，比赛演示是否接受只读 + 提案 + 明确阻断，
   还是必须调整架构后再宣称闭环？
7. **全员：** 31 天读取上限、提案有效期、幂等记录保留期、
   `readback_pending` 的恢复流程和跨用户资源的
   `FORBIDDEN/NOT_FOUND` 策略应采用哪些最终值？

这些问题阻塞 Task 2 的生产身份/版本设计及 Task 3 的全部真实写入，但不阻塞
M1 使用 Mock 验证工具映射，也不阻塞 M2 使用 DTO 开发纯函数调度器。
