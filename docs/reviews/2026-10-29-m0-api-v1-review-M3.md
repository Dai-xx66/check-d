# M0 Agent API v1 契约评审 —— M3（评估）视角

- **评审对象**：`docs/contracts/agent-api-v1.md` + `agent-api-v1.examples.json`，commit `503210c`（分支 `feat/m0-api-contract`）
- **评审范围**：错误状态、`readback_pending`、版本冲突、失败场景的验收标准
- **评审方式**：契约全文对照 CheckD 真实代码（`main@b7a16db` 起的工作分支，含 `lib/features/*` 与 `lib/core/database`）
- **未改动**：本文件不修改 `docs/contracts/`，也未合并 `feat/m0-api-contract`
- **结论**：**有条件同意冻结**。读取侧与提案侧的自洽度足够；写入侧「可能已写、无法确认」这一段状态表达是空的，有 6 项 P0 缺口会导致验收标准写不出来（见 §2）。

---

## 1. 可以保留的设计

| # | 设计 | 为什么保留 |
|---|---|---|
| 1 | 普通读取的 `query_version` 与 `base_version` 显式分离（§6.1、§6.2、§7.2） | 直接消除了「两次读取能否拼成一致快照」的歧义。这是本版最重要的一处收紧，建议冻结时不要回退。 |
| 2 | `schedule_one_time` 只持久化 `planned_date` + 可选 `scheduled_at`，`end_at`/`duration_seconds` 不进入回读断言（§5.6） | 与真实模型一致：`effectivePlannedDate` 只认 `scheduledAt ?? plannedDate`（`task_models.dart:69-73`），没有结束时间列。若按 block 的 `end_at` 断言，回读必然假失败。 |
| 3 | `readback_verified` 必须为 `true` 才算成功，不一致返回 `READBACK_MISMATCH` 且不得返回成功（§6.5） | 给出了一条可判定的硬断言，验收可以写成「响应码 + 数据双重检查」。 |
| 4 | 幂等作用域 `user + tool + key` + 请求摘要 + `IDEMPOTENCY_CONFLICT`（§6.5） | 双层防护方向正确：摘要不同要报冲突，不能静默复用。 |
| 5 | 结构合法但违反硬约束时 Proposal 保持 `draft`、返回 `validation_status=invalid`（§5.7、§6.4） | 避免「校验失败却伪造 validated」。这与 M3 的 E08/E09 用例口径一致。 |
| 6 | `changes` 白名单只两种，且禁止修改 Course 规则 / 长期 recurrence / TimerSession（§5.7） | 写入面收得足够小，评审可穷举验证。 |
| 7 | §9「BLOCKED 清单」显式列明未实现项 | 对评审最友好的写法，避免了「文档先行、能力后补」的误判风险。 |

## 2. 必须修改的字段或流程

### P0-1 `readback_pending` 没有可承载的状态位

**问题**：§6.5 要求服务端把**幂等记录**标为 `readback_pending`，但 §5.7 的 Proposal `status` 枚举只有 `draft / validated / pending_approval / applied / rejected / expired / failed`，没有 `applying` 与 `readback_pending`。结果：客户端拿到 `READBACK_MISMATCH` 后，无法从 Proposal 状态判断「写入可能已发生」还是「肯定没发生」。这是整个写入侧验收的根节点。

**证据**：§5.7 状态机图（`agent-api-v1.md:253-260`）只有四条出边且全部从 `pending_approval` 出发；§6.5（`:426-429`）提到的 `readback_pending` 在全文没有定义字段、归属对象或转换条件；`examples.json` 8 个示例中没有任何 readback 相关示例。

**建议**：
1. Proposal `status` 增加 `applying`、`readback_pending`；状态机补 `pending_approval → applying → (applied | readback_pending)`，`readback_pending → (applied | failed)`。
2. 或在 apply 响应增加独立字段 `idempotency_state: in_progress | committed | readback_pending | aborted`，并声明它与 Proposal `status` 的映射关系。二选一即可，但不能两者都没有。
3. 明确 `readback_pending` 的终局：同一幂等键重试只做回读；连续 N 次仍不一致 → 转 `failed` 并进入人工复核，不得无限重试。

### P0-2 apply 阶段的版本冲突没有错误码归属

**问题**：§6.5 要求核验「当前快照仍等于 `base_version`」，但 `SNAPSHOT_CONFLICT` 只在 §6.4（validate）段落出现，apply 失败时返回什么码未写。

**证据**：`agent-api-v1.md:411`（apply 校验项）与 `:133`（错误码表）之间没有显式绑定；`:392` 把 `SNAPSHOT_CONFLICT` 绑定在 validate 的语境里。

**建议**：在 §6.5 明确「版本不一致 → `SNAPSHOT_CONFLICT`（409），且该 Proposal 的 `approval_token` 同时失效，必须重新生成提案并重新审批」。否则客户端会拿旧 token 反复重试。

### P0-3 提案过期与审批过期语义混用

**问题**：`APPROVAL_EXPIRED`（403）只覆盖审批凭据过期；Proposal 自身 `expires_at` 过期时对应状态是 `expired`，但错误码表里没有对应码。validate / apply 对已过期提案应返回什么，未定义。

**证据**：错误码表 `:135` 只有 `APPROVAL_EXPIRED`；§5.7 `:247` 有 `expires_at` 字段，`:258` 有 `expired` 状态，两者之间无错误码映射。

**建议**：新增 `PROPOSAL_EXPIRED`（建议 410），与 `APPROVAL_EXPIRED` 区分；或在两处响应中同时返回 `proposal_status: expired`，并规定「状态优先于码」的判定顺序。

### P0-4 已应用过的 Proposal 用新幂等键再次 apply，行为未定义

**问题**：§6.5 写着「Proposal 必须最多成功应用一次，换一个幂等键也不能再次应用」，但没给错误码。验收无法断言第二次调用返回什么，也无法断言「没有发生第二次写入」。

**证据**：`:437-438` 只有约束描述，错误码表 14 项中无对应项；`examples.json` 无此场景。

**建议**：新增 `PROPOSAL_ALREADY_APPLIED`（409），并规定检查顺序：**先判 Proposal 是否已 applied，再判幂等键**。同时写明该响应必须携带首次应用的 `result_version`，便于客户端对账。

### P0-5 `schedule_one_time` 缺 `available_from` 与 `deadline` 的拒绝规则

**问题**：§6.4 只写「截止语义」，没有覆盖真实代码里的三条硬校验：计划日期不得早于 `available_from`、不得晚于 `deadline`、`scheduled_at` 必须与 `planned_date` 同日。前两条缺失会让调度器产出**必然写不进去**的提案。

**证据**：`lib/features/tasks/domain/task_models.dart:176-200` —— 同日校验、`availableFrom` 早于校验、日期型/精确型 deadline 越界校验，全部抛 `ArgumentError`。契约 §5.2 只重复了「同日」这一条，`:390` 只笼统写「截止语义」。

**建议**：在 §6.4 必须检查项中补 `available_from`；并在 §6.5 的 `violations` 里给出稳定 `code`，例如 `planned_before_available_from`、`planned_after_deadline`、`scheduled_at_not_same_day`。归类明确为「结构合法但违反硬约束」→ `validation_status=invalid`，不占用 `PROPOSAL_INVALID`。

### P0-6 目标 Task 已有 `scheduled_at` 时，只改 `planned_date` 必失败

**问题**：`schedule_one_time` 的可选字段设计成「`planned_date` 必填、`scheduled_at` 可选」。若目标 Task 原本已有 `scheduled_at`，change 只给一个新的 `planned_date`，落地时新旧不同日，真实代码直接抛错。契约没有规定这种情况是拒绝、还是必须同时给新的 `scheduled_at`、还是允许清空。

**证据**：`task_models.dart:168-179` —— `plannedDate` 与 `scheduledAt` 同日校验；`:69-73` —— `effectivePlannedDate` 优先取 `scheduledAt`，即旧的 `scheduled_at` 会压过新的 `planned_date`，回读也会读到旧日期，从而产生**合法的 `READBACK_MISMATCH` 死循环**。

**建议**：`schedule_one_time` 增加 `clear_scheduled_at`（布尔，默认 `false`），或规定「目标 Task 存在 `scheduled_at` 时该字段变必填」；并在 §6.5 回读断言里写明：`planned_date` 的回读对象是 `effectivePlannedDate`，不是列值本身。

### P1-7 四组错误共用 HTTP 码，客户端无法区分

`APPROVAL_REQUIRED` / `APPROVAL_EXPIRED` / `APPROVAL_UNTRUSTED` / `FORBIDDEN` 全是 403；`DEPENDENCY_UNAVAILABLE` 与 `WRITE_BLOCKED` 全是 503。前一组可以靠 `code` 区分，但「403 该弹审批框还是该报无权」是产品行为差异。建议批准类改用 428（Precondition Required），`WRITE_BLOCKED` 改用 501 或 409 + `retry_after: null`（表示不可重试）。

### P1-8 `details` 与 `violations` 没有 schema

错误 `details` 目前只有示例 `[{"field":..., "reason":...}]`，`violations` 只有「结构化约束错误数组」一句话。两者都缺稳定枚举，验收无法机器断言。建议定义 `violations[].code`（封闭集合）+ `field`（JSON Pointer）+ 可选 `meta`，并把 `reason` 降级为人类可读文本。

### P1-9 幂等键「执行中」没有响应约定

§6.5 只说并发请求「共享同一执行结果」，没说先到的第二个请求在第一个尚未结束时返回什么。建议明确：`409` + `idempotency_state: in_progress` + `Retry-After`，或 `202`。否则 T06/T07（见 §3）无法写断言。

### P1-10 `NOT_FOUND` / `FORBIDDEN` 已进错误码表，但策略未定

§8 写「最终策略由安全评审冻结」，可错误码表已经把两者都列为正式码。冻结前至少要给出按资源类型的默认选择（例如：跨用户 Task → `NOT_FOUND`；无权写入 → `FORBIDDEN`），否则 T10 只能标「待定」。

## 3. 需要补充的测试

判定口径统一为：**响应码 + Proposal 状态 + 数据断言 + 写入次数**四元组。下表可直接转成 `test/e2e/` 用例。

| ID | 场景 | 期望 | 关键断言 |
|---|---|---|---|
| T01 | 写入成功、回读读不到（模拟 RLS/同步延迟） | `READBACK_MISMATCH` + 幂等记录 `readback_pending` | 数据库写入次数 = 1；Proposal 不得为 `applied` |
| T02 | T01 之后用同一幂等键重试，回读此时可见 | `success`，`readback_verified=true` | 写入次数仍 = 1 |
| T03 | T01 之后回读始终不一致 | 转 `failed`（或约定的终局） | 不出现无限重试；有可审计的终局记录 |
| T04 | 提案 validate 后，另一设备改动 Task | apply 返回 `SNAPSHOT_CONFLICT` | 无任何写入；`approval_token` 已失效 |
| T05 | 审批 token 过期 | `APPROVAL_EXPIRED` | Proposal 不得变 `applied`；重试仍失败 |
| T06 | 提案 `expires_at` 过期 | `PROPOSAL_EXPIRED`（若采纳 P0-3） | 状态 `expired`，与 T05 可区分 |
| T07 | 两个并发请求、同一幂等键 | 仅一个进入写入 | 第二个返回 `in_progress` 或同一结果；写入次数 = 1 |
| T08 | 并发请求、不同幂等键、同一 Proposal | 只有一个成功 | 另一个 `PROPOSAL_ALREADY_APPLIED` 或 `IDEMPOTENCY_CONFLICT` |
| T09 | 同一 `(user, item, date)` 用不同 `override_id` 写两次 | 不得产生两条有效例外 | 见下方证据，当前实现会撞唯一键 |
| T10 | `planned_date` 早于 `available_from` / 晚于 `deadline` | `validation_status=invalid` + 具体 `violations[].code` | 不得返回 `PROPOSAL_INVALID` |
| T11 | 目标 Task 已有 `scheduled_at`，change 只改 `planned_date` | 拒绝或要求补 `scheduled_at` | 不得出现「写入成功但回读日期是旧的」 |
| T12 | 写入 `planned_date`，但 block 的 `end_at` 与库中无对应列 | 回读必须通过 | 防止用 `end_at` 造成假失败（反向保护 §5.6 的设计） |
| T13 | 请求体携带 `user_id` | `INVALID_ARGUMENT` | 不得静默忽略后继续 |
| T14 | 空数据、空日历 | `success` + 空数组 | 不得 404 |

**T09 的实现证据**：`lib/core/database/app_database.dart:345-369` 定义了 `DailyItemOverrideRecords`，主键是 `id`，同时有 `uniqueKeys = {userId, itemType, itemId, localDate}`；`day_schedule_repository.dart:57-80` 在 `overrideId` 为空时生成新 `uuid` 再 `insertOnConflictUpdate`。也就是说：**服务端若不复用 `existing_override_id`，会撞唯一约束**；若复用，则必须由可信读取提供该 ID（契约 §5.7 已要求，方向正确，但需要把「撞唯一键时返回什么」写进契约）。另注：`today_page.dart:368-373` 用 `{for ...} map` 按 `task.id` 索引，重复 override 会「后者覆盖前者」，UI 不报错但数据已经脏了——这正是必须由服务端约束兜住的地方。

## 4. 尚未验证的事项

1. **`readback_pending` 的终局判定权**：连续多少次回读失败算「确定失败」，由服务端自动降级还是人工介入，契约未定。
2. **幂等记录保留期与过期后重放**：保留期到期后同一键重试，是二次写入还是拒绝——直接影响 T02 的验收结论。
3. **`base_version` 的粒度**：是单表 `updated_at` 最大值、跨表组合，还是独立版本表；删除操作如何体现（删除往往不改 `updated_at`）。
4. **`approval_token` 是一次性还是可安全重放**：§6.5 写的是「一次性**或**可安全重放」，两种的安全测试完全不同，冻结前必须二选一。
5. **跨用户资源 `FORBIDDEN` / `NOT_FOUND` 的最终策略**（与 §2 P1-10 同一问题）。
6. **WorkBuddy 确认信号是否可验证**（属 A 的范围，但 C 的 T05/T06 端到端用例依赖它）。
7. **演示降级口径**：在写入链路 BLOCKED 的前提下，比赛演示是否接受「只读 + 提案 + 明确阻断」。M3 的意见是：**接受**，但必须在演示脚本里显式说出「此步被阻断及原因」，而不是用 Mock 成功结果代替。

## 5. 对是否冻结的建议

**建议：修完 P0-1 ~ P0-6 的**文档级**描述后即可冻结 v1；P1 项可以留到 v1.1。**

理由：6 个 P0 都能在纯文档层面解决（补状态位、补错误码、补字段、补校验项），不依赖任何 BLOCKED 能力。而 P1 里的 `details` / `violations` schema 一旦冻结后再改，会影响 Mock、演示脚本与 M2 的返回结构，属于「早改便宜、晚改贵」的项，建议至少把 P1-8 一起做掉。

不建议现在冻结的唯一情形：如果队长希望 v1 冻结后不再修订，那么 P1-8（schema）与 P1-9（并发响应）也应一并纳入，否则 T07/T08 的验收标准只能写「待定」。

---

## 附 A：示例文件覆盖缺口

`agent-api-v1.examples.json` 共 8 个示例，其中错误响应仅 2 个（`unauthorized_request`、`apply_is_blocked_without_trusted_approval`）。14 个错误码中有 12 个没有任何示例，`readback_pending`、`SNAPSHOT_CONFLICT`、`IDEMPOTENCY_CONFLICT`、`violations` 均为零示例。建议按 §3 的 T01–T14 补齐 `examples`，这同时就是验收夹具。

## 附 B：与 M3 既有边界用例的映射

`fixtures/education/boundary_cases.json` 的 13 条用例可对应到本次评审项：

| M3 用例 | 对应本评审 |
|---|---|
| E08 重复批准同一提案 | T07、T08 + P0-4 |
| E09 审批后原日历被其他设备修改 | T04 + P0-2 |
| E10 登录失效 / 跨用户访问 | T13 + P1-10 |
| E11 工具超时 / 网络错误 | P1-7 + P1-9（`readback_pending` 的触发点） |
| E03 截止日期已过 | P0-5 |
| E04 时间块跨越零点 | 需确认 `end_minute=1440` 在 `upsert_daily_override` 下的落地 |
| E12 LLM 错误提议移动固定课程 | 已由 §5.7 禁止清单覆盖（无缺口） |

E01/E02/E05/E06/E07/E13 属调度与安全侧，归 B 与 A，本评审不重复。
