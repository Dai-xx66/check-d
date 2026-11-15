# CheckD 持续智能规划系统架构（离线原型阶段）

## 边界与数据权威

Flutter Drift 是离线优先的即时交互数据源，Supabase 是已同步数据的云端副本与跨设备入口；二者不是实时强一致。任务定义继续由 `tasks`/本地任务表拥有。**在本次交付基于的 Git 基线**，`one_time_reminders`（本地主键 `task_id`）含 `scheduled_at`、`has_scheduled_date`、提醒字段和完成字段；日期型/精确截止、`planned_date` 与 `available_from` 不在该基线的 `TaskDetails` DTO 中，因此只读规划不得伪造这些值。周期规则与完成事实分别来自 `long_term_tasks`/`task_schedules` 与 `task_completions`，实际时间只来自 `timer_sessions`。不得把计划写成实际计时或完成事实。

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

候选 MCP 中的 `confirmation_text` 不能证明用户亲自确认；生产审批必须来自受验证的 WorkBuddy 人工确认节点或 CheckD 自有确认页面的服务端回调。当前目标租户的可信确认信号尚未实测，因此 `approve_schedule_proposal` 和所有真实写入仍 BLOCKED。SQLite 原型仅接受 `LocalTestHumanConfirmation` 这种显式测试接缝，用于测试 user/proposal/change digest 绑定；该类型可由测试代码构造，不是密码学凭据、OAuth 声明或生产审批证明。

尚未验证的 WorkBuddy Streamable HTTP/OAuth、Connector 发布、redirect URI 白名单、scope UI、平台审核和回调能力必须在官方开发者环境实测；本轮未注册工具或部署端点。

## 隔离快照与远程 MCP 原型（2026-11-15）

`tools/checkd_planning_engine/trusted_snapshot_store.py` 是本地临时 SQLite 原型：云端状态由带单调 revision 与内容摘要的 fixture 表模拟；设备水位分别记录 local/uploaded/downloaded revision。存在未上传本地修改或设备未确认最新云版本时，快照仍可展示，但标记 provisional 并拒绝创建 proposal。Proposal 绑定快照版本、摘要和 TTL；审批期间服务器版本改变会使其 superseded。apply 在 SQLite 事务内比较版本、消费一次性凭据、写入 allowlist 测试对象和幂等记录，再进入 readback 状态；读回恢复不重复执行写入。它没有接入 Drift SyncQueue、Supabase Auth 或真实 PostgreSQL，不能证明云端原子性。

`tools/checkd_planning_engine/remote_mcp.py` 绑定一个本地 loopback Streamable HTTP 子集，仅提供四个只读规划工具。每次请求验证 bearer、audience、expiry、scope 和显式 WorkBuddy subject → CheckD subject 映射，数据提供器只按已验证的 CheckD subject 读取；拒绝请求体 `user_id`。测试 issuer 为本地 HMAC fixture；生产侧只有注入式 introspection 边界，没有 OAuth 授权服务器、Supabase 身份绑定或 WorkBuddy 部署。读接口响应始终不具备写入资格。

## WorkBuddy 官方文档核实（2026-11-15）

腾讯 WorkBuddy 专家文档说明，专家可声明 MCP/Connector 依赖；Connector 文档列出 stdio、SSE 与 Streamable HTTP，并推荐云端托管 OAuth `auth_mode: "server-side"`。该方式需要 `server_auth` 配置并与 WorkBuddy 团队协作；文档还说明平台会托管并注入 OAuth 凭据（[专家文档](https://open.workbuddy.cn/en/docs/expert)、[Connector 文档](https://open.workbuddy.cn/docs/connector)）。Connector 文档同时描述 MCP OAuth 动态注册或预注册路径和资源元数据发现。腾讯云 Enterprise Connector 文档列出 MCP OAuth 2.1 / Streamable HTTP 与 token introspection（[Enterprise Connector 文档](https://cloud.tencent.com.cn/document/product/1831/134453)）。

这些公开文档证明存在平台接入路径，不证明当前 CheckD 账号、目标 WorkBuddy 版本、个人/企业租户或公开专家分享已经开通。开发骨架当前只模拟 MCP/身份边界，尚未实现文档要求的 OAuth 或 WorkBuddy 连接器。WorkBuddy `sub` 与 CheckD `auth.users.id` 仍是不同身份域；服务端必须完成显式账户绑定，每次请求校验授权与撤销状态，再把已绑定的 CheckD 主体注入业务数据服务。绑定、撤权、scope、令牌生命周期、客户端版本、企业权限、Connector 审核与实际调用仍须在获准的测试租户实测。共享 Connector 统一凭据不满足每个 CheckD 用户使用个人业务账号的要求。

## Flutter 本地规划预览（2026-11-15）

新增 `LocalPlanningEngine` 将既有 `checkd.planning.snapshot.v1` Drift 快照直接在 Dart 中计算，规划页默认不再依赖本机 Python/HTTP 桥接。它使用 CheckD 课程 occurrence 和已有安排作为忙碌时段，生成只读候选块、风险提示与“明天再做”比较；所有结果保持 `execution_eligible=false`。Dart 实现是独立于 Python 参考实现的启发式实现，未声明结果完全等价；手机端可运行也不代表具备生产审批或写入资格。

当前基线的 `TaskDetails` 缺少可持久化的日期型/精确截止及 `available_from` 字段，剩余工作量聚合也为空。因此规划器保留缺失信息，允许用户只为本次计算补充临时耗时/截止日期，不写回任务。Stage 14A 字段依赖须由其变更单独合入并核验后，才能从任务模型传入这些持久值；本次不改任务模型或数据库。

本次未使用 Supabase 配置启动云端会话。当前代码在登录后自动启动云端下载/上传；运行带凭证的 App 前，须先确认待同步操作是否安全。此次开发预览只在隔离测试数据库中验证，不访问或改变用户会话数据。

基础验证：最新完整 Flutter 测试 241 项通过；本地规划器定向测试 10 项通过；Python 原型测试 88 项通过；Dart 定向分析无问题。此前尝试 iOS Simulator 时，SQLite 原生库下载超时；本阶段按 Android First 决策暂停 iOS。Stage 14A 截止/最早开始字段、真实服务端可信快照、审批写入、WorkBuddy 测试租户 OAuth 仍未接入。

## Android First 验收（2026-11-15）

Android SDK 36、Emulator 37.1 和 platform/build-tools 已安装，现有 AVD `CheckD_OCR_Test`、`Pixel_9` 未使用。为保护现有模拟器数据，新建 `CheckD_Planning_Isolated` 空 AVD。`android/app/build.gradle.kts` 曾在配置阶段无条件强转缺失的 Release `key.properties`，使 Debug 也无法配置；现在仅在四项 Release 签名字段全部存在时创建 Release signing config。没有创建或写入密钥。

`flutter build apk --debug` 已成功，`flutter run -d emulator-5554 --debug` 已在隔离 AVD 启动。离线体验模式进入 Today 后，点击“智能规划预览”实际读取该 AVD 的 Drift 数据；在 AVD 中创建的合成任务 `Planning_demo` 显示工作量和截止时间未知，补充本次 60 分钟及日期后得到候选块 `18:27–19:27`；“明天再做”返回延期前后均找到安排。该任务只在新建隔离 AVD 的离线 Drift 内，未发送到 Supabase。实际模拟器本轮没有录入课程，因此课程避让由 Flutter/Dart 测试覆盖，尚无 AVD 课程 UI 场景证据。规划只读，候选参数未写回任务。

Android SDK license 在 `flutter doctor` 中仍显示未确认，但当前已安装 SDK 仍可完成 Debug 构建和模拟器运行。`flutter doctor --android-licenses` 未由自动化代理代为接受。
