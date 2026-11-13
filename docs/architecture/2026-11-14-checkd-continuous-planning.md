# CheckD 持续智能规划系统架构（离线原型阶段）

## 边界与数据权威

Flutter Drift 是离线优先的即时交互数据源，Supabase 是已同步数据的云端副本与跨设备入口；二者不是实时强一致。任务定义继续由 `tasks`/本地任务表拥有，单次事项排期语义来自 `one_time_reminders`（主键 `task_id`，`scheduled_at`、`has_scheduled_date`、`planned_date`、`available_from`、`due_date`、`due_at`）；周期规则与完成事实分别来自 `long_term_tasks`/`task_schedules` 与 `task_completions`，实际时间只来自 `timer_sessions`。不得把计划写成实际计时或完成事实。

规划层只消费一个带用户主体、数据版本、采集时间、同步状态和已解析课程 occurrence 的快照。课程 occurrence 必须由 Flutter 的 `buildCourseOccurrencesForDate`、`courseWeekNumberForDate`、`isCourseRuleActiveOnDate` 适配器生成；Python 不复制学期、单双周、停课、补课算法。

## 本地变更与云端旧快照

推荐先采用保守的两阶段快照规则：

1. 每个快照带服务端版本/同步游标、关键记录更新时间摘要及 `captured_at`。
2. 只要客户端存在待同步队列或快照过期，方案标记 `provisional`，禁止审批/写入。
3. 用户审批前重新读取任务、课程 occurrence、计时事实与现有计划，重算 digest；版本不一致则使 proposal 失效。
4. 最终写入需在服务端事务中比较 `base_version`、消费一次性 approval、应用白名单变化并回读。

单靠 `updated_at` 快照不能消除并发窗口；单靠云端版本不能识别尚未上传的设备修改。因此真正闭环还需客户端同步水位/待同步状态信号，以及服务端原子版本检查。当前仓库未提供 Agent 专用一致快照或原子排程写服务，这些生产能力仍阻塞。

## 规划模型

候选实体：`TaskEffort(user_id, task_id, estimated_total_seconds, remaining_seconds, confidence, source, updated_at)`；`PlanVersion(user_id, plan_id, version, status, basis_snapshot, created_at, approved_at, applied_at)`；`TimeBlock(user_id, block_id, task_id, plan_version_id, starts_at, ends_at, planned_seconds, status, source)`；`PlanningConstraint(user_id, constraint_id, type, hardness, effective_range, source, priority)`；`RiskAssessment(user_id, task_id, evaluated_at, feasible, available_capacity, required_effort, slack, risk_reasons)`；`ScheduleProposal(user_id, proposal_id, basis_version, proposed/removed/changed blocks, conflicts, approval_status)`。这些均为设计 DTO，不是现有 Supabase 表。

每用户私有工作空间还包含 preference、memory、risk、approval、event、idempotency 和 notification；所有键和唯一约束都以 `user_id` 为隔离边界。跨用户共享项目未来必须由显式授权关系扩展，本轮不支持。

## 组件职责与恢复

- WorkBuddy：对话与明确确认，不是身份权威或调度算法。
- 远程 MCP：OAuth 会话解析、主体注入、工具授权和结构化错误。
- 规划服务：只对已验证主体的快照运行纯函数，输出候选方案与证据。
- 审批/应用服务：再次校验版本、一次性审批与幂等键，原子应用，再权威回读。
- Flutter：产生真实课程 occurrence、同步本地改动、呈现并确认计划。

推荐长期后台方案为 Supabase Scheduled Edge Function/调度器触发无状态扫描，再将事件持久入队；规模扩大后使用独立 Worker。DB trigger 仅适合产生轻量事件，避免在事务内跑排程。用户 Mac 不应成为正式常驻 Worker。原型 SQLite 事件账本演示 user-scoped dedupe、lease、retry、重启恢复和结果归属检查。

## 多用户 WorkBuddy 与威胁模型

一个公开专家可服务多人，但 WorkBuddy 身份与 CheckD `auth.users.id` 是不同命名空间，必须完成明确 OAuth 绑定。建议 WorkBuddy 获得 CheckD 服务端 OAuth 授权码后，由后端验证 CheckD 身份并签发短时、限定 scope 的访问上下文；MCP 从受验证的 token/JWKS 或后端 session 得到主体，忽略/拒绝任何请求体 `user_id`。WorkBuddy 平台登录本身不能代替 CheckD 授权。不得复用负责人的 JWT、Keychain 或 service_role。

授权撤销需由服务端 session/token 撤销或短 TTL + introspection 生效；过期、撤销、主体不明时 fail closed。审批凭据绑定 user、proposal、base version、digest、过期时间并一次消费。幂等唯一域为 `(user_id, tool, key)`。后台扫描逐用户取数、事件写入 user_id 并以主体重验应用结果。

尚未验证的 WorkBuddy Streamable HTTP/OAuth、Connector 发布、redirect URI 白名单、scope UI、平台审核和回调能力必须在官方开发者环境实测；本轮未注册工具或部署端点。
