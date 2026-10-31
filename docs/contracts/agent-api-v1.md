# CheckD Agent API v1 契约

状态：**v1 CANDIDATE / 待 M0、M1、M2、M3 共同评审，尚未冻结**  
契约版本：`checkd.agent.v1`  
业务时区：`Asia/Shanghai`

> 本文定义拟建的 Agent 工具协议，不代表仓库中已经存在远程服务器、
> WorkBuddy 工具、审批服务或可用的生产 API。当前可确认的能力、拟建能力和
> BLOCKED 项在文末分别列出。

## 1. 目标与非目标

v1 CANDIDATE 定义七个拟建工具：

1. `list_tasks`
2. `get_calendar_events`
3. `generate_schedule`
4. `validate_schedule`
5. `request_approval`
6. `get_approval_status`
7. `apply_approved_changes`

七工具是本轮队长决策。`request_approval` 只建立待确认审批并返回外部确认入口，
`get_approval_status` 只查询外部确认结果并在满足条件时交付服务端签发的一次性
凭据。v1 不增加 `approve_schedule` 或 `reject_schedule`：模型调用工具、自然语言
回复“确认”或重复轮询都不能代表用户批准或拒绝，批准/拒绝只能发生在受控的
外部确认界面。

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

v1 比赛演示的身份模式固定为 `static_bearer_demo`：每个部署实例只绑定一个专用
演示账号，服务端把预配置 bearer token 映射到该演示账号；只允许虚拟数据或
明确隔离的专用演示数据。token 只能通过部署环境或受控连接器配置注入，不得写入
请求体、Prompt、Mock、截图、日志或仓库。该模式不是终端用户 SSO，不能区分共享
Agent 链接的不同访问者，也不得描述为真实用户认证。真实用户 OAuth/SSO、token
签发轮换和 WorkBuddy 终端身份透传保持 **BLOCKED**。

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
| `FORBIDDEN` | 403 | 与具体资源存在性无关的操作级权限拒绝 |
| `INVALID_ARGUMENT` | 400 | 字段、日期、时区或联合类型无效 |
| `NOT_FOUND` | 404 | 资源不存在或属于其他用户；两种响应必须不可区分 |
| `DEPENDENCY_UNAVAILABLE` | 503 | 读取、调度或持久化依赖不可用 |
| `PROPOSAL_INVALID` | 422 | Proposal JSON 结构、类型、未知字段或 change 类型无效 |
| `PROPOSAL_EXPIRED` | 409 | Proposal 的 30 分钟有效期已结束，必须重新生成 |
| `SNAPSHOT_CONFLICT` | 409 | 当前可信版本与提案 `base_version` 不一致 |
| `APPROVAL_REQUIRED` | 403 | 尚未为 Proposal 建立审批，或已批准但 apply 未提供凭据 |
| `APPROVAL_PENDING` | 409 | 审批已建立，但用户尚未在外部界面决定；零写入 |
| `APPROVAL_REJECTED` | 403 | 用户已在外部界面拒绝提案 |
| `APPROVAL_EXPIRED` | 403 | 审批已过期 |
| `APPROVAL_UNTRUSTED` | 403 | 审批签名、主体或提案绑定无效 |
| `APPROVAL_CONSUMED` | 409 | 一次性审批 Token 已被成功消费 |
| `ALREADY_APPLIED` | 409 | Proposal 已成功应用；换幂等键也不得再次写入 |
| `IDEMPOTENCY_IN_PROGRESS` | 409 | 同作用域同摘要请求正在 `applying`；可稍后重试，不得启动第二次写入 |
| `IDEMPOTENCY_CONFLICT` | 409 | 相同幂等键被用于不同请求 |
| `WRITE_BLOCKED` | 503 | 原子写入、RLS、同步收敛或审批链尚未实证 |
| `READBACK_PENDING` | 503 | 写入可能已发生但回读尚无终局；只允许安全回读，不得重写 |
| `READBACK_MISMATCH` | 502 | 写后回读与批准内容不一致；不得返回成功 |
| `INTERNAL_ERROR` | 500 | 已脱敏的未知服务错误 |

`IDEMPOTENCY_IN_PROGRESS` 的 HTTP 建议码固定为 409，且 `retryable=true`。
`READBACK_PENDING` 的错误详情必须包含 `proposal_status=readback_pending`；
`READBACK_MISMATCH` 必须包含 `proposal_status=failed`。错误详情不得包含原始 Token、
任务内容或完整 payload。

资源级防枚举规则适用于 Task、Course、Override、Proposal、Approval 等全部资源：
资源不存在与资源属于其他用户统一返回完全相同的 `NOT_FOUND`。`FORBIDDEN` 仅用于
“该演示主体没有执行某类操作的权限”等不依赖具体资源是否存在的拒绝。

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
- `remaining_minutes_today`：可空非负整数，仅适用于服务端可信调度快照中的周期
  任务；由 TimerSession/Completion 等事实折算，不暴露原始流水。为 `0` 时当天
  不再排程；普通 `list_tasks` 可以省略，模型不得自行计算或覆盖。
- `scheduling_weight`：可空整数，仅适用于服务端可信调度快照中的周期任务；由
  服务端可复现规则生成，用于同等硬约束下稳定排序。普通读取可以省略，模型不得
  用自然语言理由伪造权重。具体计算算法尚未实现，保持 **BLOCKED**。

单次事项不得包含 `recurrence`。周期任务不得包含单次事项的
`available_from/planned_date/scheduled_at/deadline`。

#### 内部调度 Fixture（不是远程工具请求）

`remaining_minutes_today` 只由服务端快照适配层传给 M2 内部纯函数，禁止出现在
`generate_schedule` 的远程请求参数中。必须固定以下两个独立 Fixture：

1. `remaining_minutes_today=0`：不生成 block、不进入 `unplanned_tasks`，仅产生
   `ALREADY_DONE_TODAY` explanation；不得进入最低时长兜底。
2. `remaining_minutes_today=40` 且完整 `duration_target_seconds=7200`：只生成
   40 分钟 block，`duration_seconds=2400`，`duration_source=task_target`。

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

同一单次事项在一个提案中最多出现一个可持久化 block。同一周期任务在同一个
上海本地日最多出现一个 block。每个 block 的 `start_at` 与 `end_at` 必须属于
同一个上海本地日，不能跨午夜。需要拆解的大任务应由上游先产生多个独立 Task；
v1 不把一个 Task 的多个 block 假装成现有能力。

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

调度时长来源优先级固定为：`duration_target_seconds`（周期任务使用折算后的
`remaining_minutes_today`；该字段为 null 时使用完整目标，为 0 时不生成 block）
→ 服务端可信快照估算 →
`max(preferences.minimum_block_minutes, 30)` 分钟。使用任务目标时必须标记
`duration_source=task_target`；后两种来源必须标记
`duration_source=scheduler_estimate`。任何估算都不得写回 Task 持久化字段。

快照自身可能包含相互重叠的固定课程或外部固定事件。这是合法输入；调度器只能
绕开这些固定块的并集，不得移动它们，也不得仅因“固定块彼此重叠”把 Proposal
判为违规。只有提案 block 与固定块冲突才产生约束错误。

### 5.7 `schedule_proposal`

- `proposal_id`：服务端生成的不透明 ID。
- `snapshot_ref`：服务端创建并保存的 Agent 调度快照引用；客户端和模型不得构造。
- `base_version`：与 `snapshot_ref` 绑定、由可信服务产生的版本标识。
- `input_digest`：服务端对规范化调度输入生成的摘要，覆盖 Task、有效日历事件、
  单日例外、偏好以及外部固定事件；客户端提供的摘要不可信。
- `status`：`draft`、`pending_approval`、`applying`、`readback_pending`、
  `applied`、`rejected`、`expired` 或 `failed`。
- `generated_at`：服务端生成 Proposal 的带偏移 instant。
- `expires_at`：带偏移 instant。
- `blocks`：提案展示块。
- `changes`：允许持久化的变更。
- `unplanned_tasks`：无法安排的 Task 数组；每项至少包含 `task_id`、机器可读
  `reason_code`、`remaining_minutes` 和安全的 `message`。v1 原因枚举为
  `WINDOW_INSUFFICIENT`、`PAST_DEADLINE`、`OVERLAPS_FIXED`、
  `NO_AVAILABILITY`。未安排不等于完成或跳过。
- `explanations`：对象数组；每项包含机器可读 `code` 和安全的 `message`，可选
  `related_task_ids`。不再允许字符串与对象混用。公开 `code` 是封闭枚举：
  `SCHEDULED`、`ESTIMATED_DURATION`、`ALREADY_DONE_TODAY`、
  `FIXED_BLOCKS_OVERLAP`、`NO_AVAILABILITY_WINDOW`、
  `AVAILABILITY_SATURATED`、`PRESERVED_FIXED_EVENTS`。

`DISPLACED_BY_FIXED` 与 `REPAIR_SUMMARY` 仅供 M2 内部 repair 逻辑使用，禁止出现在
v1 公开 Proposal、Mock 或远程响应中。

完整 Proposal 的服务端序列化采用方案 A：M2 纯调度函数只输出内部调度结果，
不得生成或输出 `proposal_id`、`snapshot_ref`、`base_version`、`input_digest`、
`generated_at`、`expires_at` 或 `status`。服务端包装层负责生成并持久化这些字段，
再把内部 blocks/changes/unplanned/explanations 组装成完整 Proposal。

状态机固定为：

```text
draft ──validate(valid)──→ pending_approval ──apply──→ applying ──readback ok──→ applied
  │                              │                       ├─uncertain──→ readback_pending
  │                              ├─external reject──────→ rejected    └─safe failure→ failed
  └─30 min / base changed───────→ expired
                                 └─30 min───────────────→ expired
readback_pending ──authoritative match──→ applied
readback_pending ──authoritative mismatch─→ failed
readback_pending ──still unknown───────→ readback_pending
```

结构合法但硬约束校验失败时 Proposal 保持 `draft`，通过修改输入重新生成，而不是
伪造已验证状态。Proposal 自 `generated_at` 起固定有效 30 分钟；服务端不得接受
客户端指定或延长该 TTL。基础数据版本变化即使发生在 30 分钟内，也必须返回
`SNAPSHOT_CONFLICT` 并重新验证或重新生成。`readback_pending` 表示写入可能已经
发生，只能用同一幂等请求继续回读，不能再次写入。

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

`input_digest` 的规范算法固定为：对一次服务端一致性快照映射出的调度输入进行
规范化 JSON 编码（对象键按字典序、数组按契约规定的稳定键排序、时间统一为带
偏移 RFC 3339、不包含仅展示用空白差异），再计算 SHA-256 并输出小写十六进制。
摘要输入必须覆盖可信 Task、Course、有效 Calendar Event、Daily Override、外部
固定事件、调度偏好、调度 horizon 的起止 instant 和固定时区
`Asia/Shanghai`。其他输入完全相同时，只要 horizon 不同，摘要就必须不同。普通
`list_tasks` 与 `get_calendar_events` 响应不得由客户端拼接后计算该摘要。

远程服务执行单日例外时还必须验证：`item_id` 属于当前已认证用户、资源真实
存在、`item_type` 与实际资源类型一致、`existing_override_id`（若有）属于同一
用户，以及 action 位于 v1 白名单。现有 Repository 的参数校验不能替代这些
远程权限检查。

同一 `user + item_type + item_id + local_date` 只能存在一个有效单日例外。若快照
之后该键已经出现新记录，或 `existing_override_id` 与当前记录不一致，返回
`SNAPSHOT_CONFLICT` 且零写入；不得用另一个 `override_id` 创建重复记录。

禁止的 change：修改 Course 规则、修改周期任务长期 recurrence、创建或修改
TimerSession、修改完成记录、修改统计、写入多个单次事项未来块。

执行 `schedule_one_time` 还必须验证 `planned_date >= available_from`（若有）且不
违反日期型或精确截止。`scheduled_at` 可省略、为 null 或为带偏移 instant：省略
表示保留现值，null 表示清除现值；如果保留后的 `scheduled_at` 与新的
`planned_date` 不在同一上海本地日，必须以 `PROPOSAL_INVALID` 拒绝，不能出现
“写入成功但有效计划日期仍来自旧 scheduled_at”的假成功。

`skip` 不属于 v1 change 白名单。排不下的任务只能留在 `unplanned_tasks` 中作为
非持久化建议，不写入单日例外，不修改完成状态、TimerSession 或周期规则。

### 5.8 `violation`

`validate_schedule.violations` 使用统一对象结构：

- `code`：必填，机器可读封闭枚举。
- `message`：必填，安全且可展示。
- `related_task_ids`、`related_block_ids`、`related_event_ids`：可选字符串数组。
- `field`：可选，指向规范字段路径。

公开 `code` 的 v1 完整闭集仅为：`PLANNED_BEFORE_AVAILABLE_FROM`、
`PLANNED_AFTER_DATE_ONLY_DEADLINE`、`BLOCK_AFTER_EXACT_DEADLINE`、
`BLOCK_TIME_INVALID`、`FIXED_EVENT_CONFLICT`、
`MULTIPLE_CHANGES_FOR_ONE_TIME_TASK`、
`MULTIPLE_BLOCKS_FOR_RECURRING_TASK_DAY`。未知 `code` 必须以 `PROPOSAL_INVALID`
拒绝，不得作为“扩展解释”透传给远程调用方。

结构或联合类型错误（例如 `scheduled_at` 与 `planned_date` 跨上海本地日）返回
`PROPOSAL_INVALID`，不放入 violations。结构合法但计划日期早于 `available_from`
使用 `PLANNED_BEFORE_AVAILABLE_FROM`；晚于 date-only deadline 使用
`PLANNED_AFTER_DATE_ONLY_DEADLINE`；block 结束晚于精确截止使用
`BLOCK_AFTER_EXACT_DEADLINE`。

## 6. 工具契约

| 工具 | 关键输入 | 关键输出 | 权限/写入边界 | 状态变化 |
|---|---|---|---|---|
| `list_tasks` | `date_range`、筛选项 | 去重 Task、`query_version` | 仅当前演示主体，只读 | 无 |
| `get_calendar_events` | `date_range`、外部固定事件 | occurrence、Course、Override、`query_version` | 仅当前演示主体；外部事件不落库 | 无 |
| `generate_schedule` | 范围、外部事件、偏好 | `draft` Proposal、可信快照引用 | 服务端读取可信数据；只创建提案 | 创建 `draft`，TTL 30 分钟 |
| `validate_schedule` | `proposal_id` | 校验状态、violations | 只能校验当前主体 Proposal；零业务写入 | `draft → pending_approval`；无效保持 `draft` |
| `request_approval` | `proposal_id`、幂等键 | `approval_id`、外部 `approval_url` | 不批准、不签 Token；只建审批记录 | Proposal 不变；Approval 创建为 `pending` |
| `get_approval_status` | `approval_id` | 审批状态；批准后首次安全交付 Token | 不替用户决定；只读/受控 Token 签发 | 外部决定可使 Proposal `rejected/expired`；Approval 可到 `token_issued` |
| `apply_approved_changes` | Proposal/version/Token/幂等键 | 实际变更、结果版本、回读结果 | 唯一业务写工具；仅白名单 change | `pending_approval → applying → applied/readback_pending/failed` |

所有工具都要求 `static_bearer_demo` 映射出的演示主体。除
`apply_approved_changes` 外不得写 Task、Override、TimerSession、Completion、Course
或统计事实；两个审批工具只能写审批域记录。

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
测试；这是内部接口，不等于远程工具可以信任这些 DTO。M2 只返回内部调度结果，
不得返回 Proposal 服务端信封字段；服务端包装层按 5.7 的方案 A 完成序列化。

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
- `approval_readiness`：合法但尚未调用 `request_approval` 的提案为
  `not_requested`；约束失败为 `not_approvable`。该字段只表达“能否进入审批”，
  不表达真实 Approval 生命周期。
- `violations`：结构化约束错误数组。
- `validated_at`、`expires_at`：带偏移 instant。

结构/类型/未知字段错误返回 `PROPOSAL_INVALID`。结构合法但违反调度硬约束时返回
成功响应、`validation_status=invalid` 和结构化 `violations`，Proposal 保持
`draft` 且不能审批。

必须检查：身份所有权、版本、输入摘要、时间格式、截止语义、固定事件冲突、同一单次事项
最多一个 block、同一周期任务单日最多一个 block、block 不跨上海本地日、change
白名单、单日例外日期、Task/Course 存在性。服务端必须从一次一致性快照重新生成
规范化 JSON，并以 SHA-256 重算 `input_digest`；不得拼接两次普通读取。版本或摘要
不一致返回 `SNAPSHOT_CONFLICT`。Proposal 已过期返回 `PROPOSAL_EXPIRED`。
`valid` 不等于已批准。

### 6.5 `request_approval`

**用途：** 为已验证且未过期的 Proposal 创建或取得一个待用户外部确认的审批
请求。调用该工具不等于用户批准，不签发 `approval_token`。

请求 `input`：

- `proposal_id`：必填；必须属于当前认证主体且状态为 `pending_approval`。
- `idempotency_key`：必填；作用域为
  `authenticated_user_id + request_approval + idempotency_key`。

成功 `data`：

- `approval_id`：服务端生成的不透明审批 ID。
- `proposal_id`。
- `status`：固定为 `pending`。
- `approval_url`：受控外部确认页面；不得包含 bearer token 或审批 Token。
- `expires_at`：不得晚于 Proposal 的 `expires_at`。

同一用户、同一 Proposal 在已有未终结审批时重复请求，必须返回同一个
`approval_id`；同一幂等键用于其他 Proposal 返回 `IDEMPOTENCY_CONFLICT`。
Proposal 已过期返回 `PROPOSAL_EXPIRED`，已应用返回 `ALREADY_APPLIED`，不得创建
新的审批。审批服务及页面尚未实现，真实调用保持 **BLOCKED**。

一个 Proposal 同时最多有一个有效 Approval。有效状态包括 `pending`、`approved`
和 `token_issued`；终结状态包括 `consumed`、`rejected`、`expired`。Token 过期但
Proposal 仍有效时，旧 Approval 转为 `expired`，允许下一次
`request_approval` 创建新的 `approval_id`；旧 Token 永远无效。Approval 的
`expires_at` 不得晚于 Proposal 的 `expires_at`。

若 Token 已签发但交付响应丢失或结果不确定，v1 保留原 Approval
的 `token_issued` 状态：Agent 不得自行推断 Token 丢失，不得撤销、替换或
重新签发 Token。`get_approval_status` 可以查询现有状态，但必须返回
`approval_token=null`，不再泄露原 Token。旧 Token 在 `now >= token_expires_at`
时过期，旧 Approval 进入 `expired`，旧 Token 永久无效。

只有在 Proposal 仍有效、旧 Approval 已终结，并且用户明确要求“重新
审批”后，Agent 才能调用普通 `request_approval`。该调用必须创建新的
`approval_id`，并完整重走外部用户确认流程。普通 Agent 请求、模型
推断、超时或布尔字段都不是用户授权。如何由服务端验证该明确
用户意图属于未来可信恢复机制，v1 真实实现保持 **BLOCKED**；不引入
recovery token、OAuth 或未实测的 WorkBuddy 回调。

### 6.6 `get_approval_status`

**用途：** 查询外部确认结果。它不能替用户批准或拒绝；模型轮询不会改变用户
决定。

请求 `input`：

- `approval_id`：必填，必须属于当前认证主体。

成功 `data`：

- `approval_id`、`proposal_id`、`status`、`expires_at`。
- `status=pending`：用户尚未决定，不返回 token。
- `status=approved`：外部确认已通过；仅首次安全交付时返回
  `approval_token`、`token_issued_at` 和 `token_expires_at`。
- `status=token_issued`：Token 已签发但尚未成功消费；后续轮询返回
  `approval_token=null`，防止重复泄露。
- `status=consumed`：Token 已成功消费。
- `status=rejected`：用户拒绝或在 Token 消费前撤回批准；Proposal 同步进入
  `rejected`，已签发但未消费的 Token 必须在同一原子操作中撤销。
- `status=expired`：该审批或 Token 已过期；若 Proposal 的 30 分钟 TTL 也已结束，
  Proposal 同步进入 `expired`。若仅 5 分钟 Token 过期而 Proposal 仍有效，Proposal
  保持 `pending_approval`，可以重新创建审批，但旧 Token 永远无效。

审批 Token 由服务端签发，模型不得构造。Token 必须绑定认证主体、
`approval_id`、`proposal_id`、`base_version`、change 摘要及有效期；TTL 固定为
签发后 5 分钟，并且 `token_expires_at` 不得晚于 Proposal 的 `expires_at`。Token
只能安全交付一次；若交付响应丢失，v1 不重新显示、撤销或替换原
Token，而是等待其按既定 TTL 过期。仅用户明确要求后才能在 Proposal
仍有效时重新走普通审批。真实签名、存储、恢复授权和外部确认身份仍为
**BLOCKED**。

Approval 生命周期固定为：

```text
pending ──external approve──→ approved ──atomic token claim──→ token_issued
   ├─external reject────────→ rejected                         ├─apply claim──→ consumed
   └─expiry─────────────────→ expired                          ├─token expiry→ expired
                                                               └─external revoke→ rejected
```

并发 `get_approval_status` 必须对 Token 交付做原子认领：最多一个请求取得非空
`approval_token`；其他并发请求返回 `status=token_issued` 且
`approval_token=null`。

Proposal、Approval 和 Token 的统一过期边界为 `now >= expires_at`。等于
`expires_at` 的瞬间已经过期，不再允许校验、签发或写入。

### 6.7 `apply_approved_changes`

**用途：** 仅在可信用户确认已被转换成服务端可验证批准状态后，原子地应用
批准的白名单变更并回读核验。

请求 `input`：

- `proposal_id`：必填。
- `base_version`：必填；必须与已验证、已批准提案及 `snapshot_ref` 绑定。
- `approval_token`：必填；不透明、服务端签发、5 分钟内有效且一次性的凭据。
- `idempotency_key`：必填；调用方生成，1–128 字符，不能包含用户数据。

服务端必须从审批存储加载原提案，不能接受请求体重新提交 `changes`。必须核验：

- 凭证主体与当前已认证用户相同。
- 凭证绑定完全相同的 `proposal_id`、`base_version` 和变更摘要。
- 凭证未过期、未撤销、未消费；模型不得生成或修改凭证。
- 当前快照仍等于 `base_version`。
- 幂等键首次使用，或与完全相同请求重复使用。
- 所有变更在同一原子边界成功；无法证明原子性时返回 `WRITE_BLOCKED`。

成功 `data`：

- `proposal_id`、`base_version`、`result_version`。
- `proposal_status`：固定为 `applied`。
- `idempotency_key`。
- `applied_changes`：实际持久化 ID 和规范化后的日期/时间。
- `readback_verified`：必须为 `true`。
- `applied_at`。
- `recovery_evidence`：仅当请求从 `readback_pending` 收敛时返回；固定包含
  `operation=readback_only`、`business_write_count_delta=0` 和
  `second_apply_executed=false`，用于证明这是状态恢复而非第二次应用。

`schedule_one_time` 的回读只核验 `planned_date` 和可选 `scheduled_at`；不得用
提案 block 的 `end_at` 作为现有模型的持久化断言。

`upsert_daily_override` 的回读必须核验实际 `override_id`、`item_type`、`item_id`、
`local_date`、`action`、`planned_start_minute` 和 `planned_end_minute`；任何字段缺失
或不同均不得返回成功。

写后必须通过授权读取路径回读。若暂时无法完成权威回读且写入结果未知，返回
`READBACK_PENDING`，Proposal 状态为 `readback_pending`；同一幂等键重试只能
重新回读，不能再次写入。若已完成权威回读并确认内容不一致，返回
`READBACK_MISMATCH`，Proposal 转为终态 `failed`，不允许再次写入。只有能够确认
事务未提交的确定性失败才可直接进入 `failed`；无法确认时必须保留
`readback_pending`。

`readback_pending` 恢复只能执行权威回读和状态收敛：回读一致时转为
`applied` 并返回原幂等结果；回读确认不一致时转为 `failed` 并返回
`READBACK_MISMATCH`；结果仍未知时保持 `readback_pending` 并返回
`READBACK_PENDING` (`retryable=true`)。三条路径的业务写入增量都必须为零。

判定顺序必须保证错误可达、防资源枚举且不二次写入：

1. 验证当前认证主体对 Proposal 的访问权；不存在与其他用户资源统一返回
   `NOT_FOUND`。
2. 验证 Token 的格式/签名、认证主体及 `approval_id/proposal_id/`
   `base_version/change_digest` 绑定。本步只判定信任与绑定，不暴露
   不属于当前 Proposal 的 Token 是否已消费。
3. 验证幂等作用域和规范请求摘要。
4. 检查 Proposal 当前状态，先处理
   `applying/readback_pending/applied/rejected/expired/failed` 的终止或收敛语义。
5. 对“绑定完全正确但已消费”的 Token：Proposal 已 `applied` 时返回
   `ALREADY_APPLIED`；Proposal 尚未 `applied`（包括 `failed`）时返回
   `APPROVAL_CONSUMED`。
6. 验证 Proposal/Approval/Token TTL 和当前 `base_version`。通过全部前置
   条件后，才能以一个原子操作消费 Token 并将 Proposal 转入
   `applying`。

- 同键不同摘要：`IDEMPOTENCY_CONFLICT`，零业务写入。
- 同键同摘要且记录正在 `applying`：HTTP 409、
  `IDEMPOTENCY_IN_PROGRESS`、`retryable=true`，零业务写入且不得无限等待。
- 同键同摘要且 Proposal 为 `readback_pending`：只继续回读；若仍无终局返回
  `READBACK_PENDING`，不得再次写入。
- 新键但 Proposal 为 `applying` 或 `readback_pending`：统一返回
  `READBACK_PENDING`，零业务写入。
- 新键但 Proposal 为 `applied`：返回 `ALREADY_APPLIED`，零业务写入。
- Proposal 为 `failed`、`rejected` 或 `expired`：均为终态，不允许再次写入。
  `failed` 且携带同 Proposal 已消费 Token 时返回 `APPROVAL_CONSUMED`；
  `retryable=false`、零业务写入，且不得重新签发 Token。按正常状态
  不变式，Proposal 只能在 Token 已原子消费并进入 `applying` 后转为
  `failed`，因此不新增一个与 `APPROVAL_CONSUMED` 重叠的 failed 错误码。

Proposal 过期返回 `PROPOSAL_EXPIRED`；Token 过期返回 `APPROVAL_EXPIRED`；版本
变化返回 `SNAPSHOT_CONFLICT`，以上均为零写入。

若 apply 时没有审批记录，返回 `APPROVAL_REQUIRED`；已有审批但仍为 pending，
返回 `APPROVAL_PENDING`；用户拒绝返回 `APPROVAL_REJECTED`。这些情况不得进入
`applying`，写入次数必须为零。

Token 在服务端通过全部前置校验后，以原子操作同时完成两件事时消费：认领该
Token，并将 Proposal 转入 `applying`。一旦消费不得恢复，即使随后发生确定性
失败。若 Proposal 已 `applied`，优先返回 `ALREADY_APPLIED`；若 Token 已消费但
Proposal 未成功应用，返回 `APPROVAL_CONSUMED`；若结果未知，返回
`READBACK_PENDING`。这保证 `APPROVAL_CONSUMED` 有独立可达路径。

`APPROVAL_UNTRUSTED` 仅用于：Token 不存在或格式无效、签名验证失败、认证主体
不匹配、`proposal_id/base_version/change_digest` 绑定不匹配，或 Token 因安全/管理
原因撤销。用户在 Token 消费前撤回批准时，绑定仍可验证，但返回
`APPROVAL_REJECTED`，不是 `APPROVAL_UNTRUSTED`。
缺少凭据使用 `APPROVAL_REQUIRED`，过期使用 `APPROVAL_EXPIRED`，已消费使用
`APPROVAL_CONSUMED`。

幂等作用域固定为 `authenticated_user_id + tool_name + idempotency_key`。服务端对
规范化的 `proposal_id/base_version/approval_id` 和白名单 change 摘要生成请求摘要；
不得把 Token 本身或 Token 前缀写入摘要或日志：

- 同一作用域、同一摘要：已完成时返回原结果；执行中返回
  `IDEMPOTENCY_IN_PROGRESS`；回读待定时只继续安全回读，不重复写入。
- 同一作用域、不同摘要：返回 `IDEMPOTENCY_CONFLICT`。
- Proposal 还必须具备“最多成功应用一次”的唯一约束，换一个幂等键也不能再次
  应用同一 Proposal。

幂等存储介质、并发锁、保留期和崩溃恢复尚未实现，继续标记 **BLOCKED**。

## 7. 审批、版本和并发安全

### 7.1 审批凭据：接口已决策，实现仍 BLOCKED

v1 CANDIDATE 采用 `request_approval` 与 `get_approval_status` 两个审批工具，但
不增加 `approve_schedule` / `reject_schedule`。可信交互层在工具之外收到用户
明确决定，审批服务验证确认者、认证主体、Proposal 摘要和有效期，持久化审批
状态；仅批准后签发绑定 `user`、`approval_id`、`proposal_id`、`snapshot_ref`、
`base_version`、`input_digest`、`change_digest` 和 `expires_at` 的一次性
`approval_token`。

固定规则：Proposal TTL 为生成后 30 分钟；Token TTL 为签发后 5 分钟且不得越过
Proposal 到期时间；Token 成功消费后不可再次使用；基础数据版本变化始终优先
阻止写入。模型文本、工具调用、轮询或 WorkBuddy 按钮本身都不是可信批准。

当前尚未实现外部确认页面、确认者登录校验、审批存储、Token 签名/撤销和
WorkBuddy 回调，因此 `apply_approved_changes` 的真实端到端写入仍为 **BLOCKED**。
Mock 只能证明协议状态流转，不得描述为生产审批。

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

- 演示只允许 `static_bearer_demo` 映射出的专用演示主体；服务端只使用该映射主体
  查询数据，不信任请求体身份。
- 所有目标 Task、Course、Override 和 Proposal 都要再次核验 owner。
- 资源不存在与资源属于其他用户均返回 `NOT_FOUND`；两者的
  `code/message/details` 必须完全不可区分。`FORBIDDEN` 仅用于与某个具体
  资源是否存在无关的操作级权限拒绝。
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

- 本文七个远程工具及其服务端路由。
- M2 调度引擎和 Proposal 持久化。
- WorkBuddy Tool Mapping。
- 审批存储、版本服务、幂等存储、原子写入和回读端点。

### BLOCKED

- WorkBuddy 可用工具协议、可信用户确认信号和身份传递。
- 真实用户 SSO/OAuth、静态演示 Token 的安全签发与轮换。
- HTTPS/平台托管服务的位置与部署方式。
- 可信跨表 `base_version` 算法与事务内比较。
- Agent 专用 `snapshot_ref` 存储、输入规范化和摘要算法。
- 审批凭据签发者、审批存储和确认事件通道。
- Supabase 线上 migration/RLS 状态、原子写入和 Drift 同步收敛。
- 生产写入与真实 Agent API 可用性。

## 10. 已决策事项与剩余 Open Questions

已经确认且除非出现新代码证据、测试失败或平台实测结果，否则不重新讨论：七个
工具、`static_bearer_demo` 演示边界、一次性 5 分钟 Token、30 分钟 Proposal、
基础版本变化强制重新验证、v1 不持久化 `skip`。

剩余问题：

1. **M0 + M1：** WorkBuddy 是否实际支持 stdio/远程 MCP、env/header 凭证、外部
   确认回调及异账号分享？审批页面与服务由谁托管？
2. **M0 + M2：** `snapshot_ref/base_version` 覆盖哪些表，内部 DTO 如何规范化，
   如何在读取和写入事务内生成/比较？
3. **M0：** 写入应经过本地 Repository/SyncQueue 还是受控服务端事务？如何证明
   两条路径最终收敛且不会覆盖离线修改？
4. **M1 + M3：** 无可信审批能力时，比赛演示是否接受只读 + 提案 + 明确阻断，
   还是必须调整架构后再宣称闭环？
5. **全员：** 31 天读取上限、幂等记录保留期，以及
   `readback_pending` 恢复作业的执行者/重试间隔尚需决定。恢复只读和
   `applied/failed/readback_pending` 收敛语义已在 5.7/6.7 冻结；跨用户资源
   的防枚举策略已在 4.1 冻结。

这些问题阻塞 Task 2 的生产身份/版本设计及 Task 3 的全部真实写入，但不阻塞
M1 使用 Mock 验证工具映射，也不阻塞 M2 使用 DTO 开发纯函数调度器。
