# CheckD 规划系统 M0–M8 路线图

状态定义：**原型实现**表示代码存在；**本地验证**表示隔离自动化测试通过；**Flutter 集成**表示可由 App provider 调用；**云端连接**表示服务端真实数据入口已运行；**生产验证**表示已获准完成双用户及恢复验证。后两者当前均未达成。

| 里程碑 | 当前状态 | 已验证的交付 | 尚缺内容与依赖 | 风险/批准边界 |
|---|---|---|---|---|
| M0 契约冻结 | 候选设计；未冻结 | `agent-planning-v0.json` 定义候选读写工具与主体边界 | M1/M2/M3 联合评审、错误/状态完整校验、最终冻结 | 生产授权和事务语义仍阻塞 |
| M1 规划数据层 | 本地原型 + 本地验证 | DTO、user-scoped 数据及新建 sync-aware `TrustedSnapshotStore` 测试；无正式新表 | 接入真实 Drift outbox 水位、服务端云快照读取、正式服务端版本 | 需人工批准任何 Production Migration/RLS |
| M2 课程与任务适配 | Flutter 集成（只读本地） | `planningSnapshotProvider` → Drift Context → canonical calendar builder → JSON；内存 Drift/双用户/课程例外测试 | 实际设备库验收、跨端同步水位、完整实时数据确认 | 全部结果暂定、不可执行 |
| M3 排程引擎 | 原型实现 + 本地验证 | EDF、时区、课程占用、固定占用、优先级、依赖、最大连续时段、延期、性质/小型穷举测试 | 更大规模基准、用户目标/约束来源、独立求解器对照 | 启发式失败不是数学无解 |
| M4 延期与风险 | 原型实现 + 本地验证 | 延期分析、容量/截止/缓冲风险、风险版本更新、提醒冷却与日限额 | Flutter UI、真实通知渠道、实际剩余工时 | 通知当前仅为本地待办 |
| M5 事件与扫描 | 本地持久原型 + 本地验证 | SQLite 租约、重试、幂等、崩溃恢复、逐用户风险和通知 outbox | 云端 Worker、调度器、监控、保留策略、可用性设计 | SQLite 不是跨设备/生产服务 |
| M6 WorkBuddy Agent | 本地 Streamable HTTP 骨架 + 协议/边界测试；未接入 WorkBuddy | 只读四工具 loopback 服务、bearer 验证接口、跨用户 subject 绑定测试；官方 Connector 路径已查证 | OAuth AS/CheckD Auth 绑定、工作区 Connector 注册/审核、目标租户/版本/分享/撤权实测、部署审批 | 测试 HMAC issuer 不是 OAuth；未部署、未连接 WorkBuddy |
| M7 审批与真实写入 | 本地 SQLite 事务模拟 + 本地验证 | 用户/提案/快照版本/变更绑定，一次性测试凭据、幂等、过期、审计、可注入事务回滚、只读回读恢复 | PostgreSQL 原子 compare-and-apply、正式授权服务、真实 CheckD allowlist、权威云端 readback | 只改变临时测试库里的模拟 cloud payload，不访问 CheckD 数据 |
| M8 反调官与偏好 | 本地策略原型 + 本地验证 | Gentle/Balanced/Direct 共用事实；偏好来源；休息冷却、每日上限、忽略、休闲平衡 | 持久化偏好产品 UI、用户研究、渠道送达 | 推断偏好不能成为硬约束 |

## 本轮状态

- **已接入 Flutter：** 本地只读规划快照有 Riverpod provider，来源为当前 App owner 对应的 user-scoped Drift Repository。没有新增页面入口，也没有连接云端规划服务。
- **已连接云端：** 无。`TrustedSnapshotStore` 仅在测试数据库模拟服务端 revision 与同步水位；Supabase 服务端可信快照、服务端版本/水位和 MCP OAuth API 均未运行。
- **多用户认证：** 未完成。HTTP skeleton 使用测试 issuer 验证主体映射，SQLite Principal 是显式 local-test seam；均不是 OAuth、Supabase JWT 验证或生产隔离证据。
- **审批写入能力：** 未完成。新 `TrustedSnapshotStore` 在隔离 SQLite 中模拟一个原子版本比较和测试用 allowlist 变更；不是 CheckD 业务写入。模拟器可在故障前回滚事务，但真实 PostgreSQL 事务和权威回读未实现。
- **生产安全验证：** 未完成。未访问 Production、未执行 SQL/Migration/RLS，也未部署或修改 WorkBuddy 生产专家。

## 推荐生产前置顺序

1. 在 Flutter 暴露事务一致、带用户身份与 dirty-range/outbox watermark 的版本化只读快照；先在脱敏设备夹具验证本地与云端差异。
2. 建立 CheckD Auth OAuth 授权码绑定与可撤销服务端 session，并以两位测试用户验证 MCP 每请求身份传播；WorkBuddy Connector 版本/租户/分享能力需先实机验证。
3. 将本地 `TrustedSnapshotStore` 语义迁移到隔离 PostgreSQL 测试库，验证事务、锁竞争、幂等及回读；由真实 OAuth principal 与服务端生成快照后，再经安全评审及人工批准讨论 Production Migration/RLS/部署。
