# CheckD 合并后集成与代码审查报告

检查日期：2026 年 11 月 23 日，Asia/Shanghai。检查对象是 GitHub 可见的 CheckD main，以及本轮独立修复。结论：已修复本地账号隔离、同步完整性和 UI 集成中的确定缺陷，组合版本 364 项测试及 Web 生产构建通过；Android、真实云端鉴权和独立桌面小窗仍有验证阻断，暂不建议直接开展使用真实个人数据的多账号联合测试。

## 基准与交付

- 上游仓库：Dai-xx66/check-d，main 基准为 PR #12 的合并提交 `be0c3c5354dbc1e4c27892dc62d3793370a39074`。提交前再次查询远端 main，仍为该提交。
- 组合审查分支：`codex/post-merge-audit`；全部代码修复的组合提交为 `b26a6742997a15af17b58a5bad84d635b9a0691e`。全量测试、分析和 Web 构建针对这组代码，不把组合测试误称为每个独立分支的全量测试。
- 四个 PR 均直接基于上述 main，各只有一个提交，彼此不堆叠。每个独立分支另外执行了相应定向测试。
- 未修改生产数据库、生产数据或线上配置；未修改数据库 schema、远端 payload 或依赖版本；不需要数据迁移。所有修复等待 M0 审核合并。

| PR | 独立分支与提交 | 范围 | 独立验证 |
| --- | --- | --- | --- |
| [PR #13](https://github.com/Dai-xx66/check-d/pull/13) | `codex/ui-integration-fixes`，`e5f75f7fe1ac7c1a99f98b7e46d5b33b894e27f3` | 外观持久化、重叠课表、Android 签名配置；5 文件 | 6 个测试文件，20 PASS |
| [PR #14](https://github.com/Dai-xx66/check-d/pull/14) | `codex/account-isolation-fixes`，`7ffe14625253981f5903ecd3fe8e907d5c9715a9` | Auth、路由、响应式 owner、8 个本地保存入口；12 文件 | 7 个测试文件，39 PASS |
| [PR #15](https://github.com/Dai-xx66/check-d/pull/15) | `codex/sync-integrity-fixes`，`f034410097768db735757e051a261b1c787a94d3` | 恢复、离线合并、墓碑、上传队列；8 文件 | 6 个测试文件，66 PASS |
| [PR #16](https://github.com/Dai-xx66/check-d/pull/16) | `codex/plan-progress-refresh`，`4d7dbb1bca6bdbee456fce7dc60768406f8c76e5` | 原有计划进度刷新；2 文件 | 4 PASS |

## 检查范围

本轮采用代码审查、内存 SQLite 业务回归、Widget 测试、模拟 HTTP 服务及本机构建，未将模拟服务视为生产端到端验证。

| 模块 | 主要代码和核查内容 |
| --- | --- |
| Auth 与页面生命周期 | `lib/features/auth/`、`lib/app/app.dart`、`account_sync_page.dart`、任务及同步 Providers；登录、退出、过期会话、账号切换、重复提交、原生 push 路由 |
| 本地数据与核心业务 | `app_database.dart`、已有迁移与迁移测试；Task、Course、Semester、DaySchedule、Tag、Plan、Review、Statistics 仓库；数据 owner、名称校验、软删除、计时与完成独立性、计划与实际事实 |
| 同步与归属 | `lib/core/sync/`、`supabase/migrations/`；恢复表与主键、版本冲突、离线合并、父子关系、重试退避、账号隔离、AppSettings 白名单 |
| UI 集成 | `lib/core/theme/`、外观设置、共享小羊/图标组件、日历与课表、统计；偏好加载和保存、资源导出、硬编码颜色、响应式布局、长标题和减少动态效果 |
| 平台与接口 | `android/app/build.gradle.kts`、桌面小窗入口、云 OCR 函数、仓库中的 WorkBuddy/MCP/OAuth 计划文档与可见实现范围 |

## 已修复问题

严重程度表示修复前的影响。High 中的账号问题均为已复现或有明确代码路径的本地边界缺陷，不代表生产云端已经发生泄露。BUILD-01 是静态确认，尚未在 Android 工具链中执行到相应阶段。没有确认 Critical 级问题。

| 编号 | 级别 | 复现条件与影响 | 修复与回归证据 | 交付 |
| --- | --- | --- | --- | --- |
| AUTH-01 | High | A 的 Repository 已缓存后退出并登录 B，owner 只读取稳定 SupabaseClient，未依赖会话事件，可能继续读取/写入 A 或离线 owner 的本机记录。 | AuthState 保存 userId、订阅会话变化，Repository owner 和同步诊断依赖响应式身份。内存 DB 验证 A 私有任务在切 B 后不可见，过期后诊断归零。 | PR #14 |
| AUTH-02 | High | 任务详情/设置经 Navigator.push 打开后退出或换账号，根 AppGate 改变但旧页面仍覆盖其上。 | 身份变化时清除原生 push 栈并回根路由。两个 Widget 回归覆盖退出与 A→B；单独 go('/') 不足以清理原生路由。 | PR #14 |
| AUTH-03 | Medium | 登录中重复提交或点击离线体验，迟到登录结果可能切换当前状态；控制器销毁或重建后也可能回写旧结果。 | 提交 guard、页面禁用、mounted/generation 检查，完成后核对真实 currentUser。回归覆盖重复操作、过期会话及迟到完成。 | PR #14 |
| AUTH-04 | Medium | 网络异常导致退出失败，原实现未显示安全错误，异常 Future 外抛。 | 捕获失败，保留当前身份，解除 submitting 并显示可重试提示。 | PR #14 |
| AUTH-05 | Low | 调试日志输出完整后端异常及 message，可能携带不必要的后端详情。 | 仅保留异常类型和 Supabase status/code，不输出原始异常全文。 | PR #14 |
| DATA-01 | High | 向课程、课程规则、模板、学期、单日例外、提醒、闹钟、临时计时保存入口传入另一账号已有 ID，upsert 会改写其 userId。8 项改前回归均失败。 | 在同一事务内检查归属、写记录和入队；拒绝已有外账号 ID，保留同账号 createdAt 与不存在的显式 ID 导入。11 项回归包括并发相同 ID 导入仅一个 owner 成功。 | PR #14 |
| SYNC-01 | High | 恢复的分段引用本机其他账号模板，或离线数据引用第三账号父记录时，原归属检查仍允许恢复/合并。 | 17 种明确父子关联由恢复与离线合并共用，覆盖模板、学期、课程、标签、任务、计时和计划。冲突先拒绝并回滚。 | PR #15 |
| SYNC-02 | High | readTable 单次 select，服务端限行后仍被当成完整恢复。模拟服务端每次上限 2 行、共有 5 行，旧查询实际只读 2 行。 | 完整主键稳定排序，按实际响应条数推进分页，核对 exact 总数；修复读取全部 5 行。支持服务端上限低于每页请求数，plan_tasks 用复合键。 | PR #15 |
| SYNC-03 | Medium | 云端删除完成/计时事实时只记墓碑，本机事实仍在统计中；旧删除快照还可能倒退屏障时间。 | 同事务删除当前用户本机事实缓存并保留墓碑；只接纳更晚的墓碑版本，旧/中间版本不能复活记录。 | PR #15 |
| SYNC-04 | Medium | 最早一整批永久失败记录占满批次，后续正常 pending 无法进入；改前新任务上传数 0，重试计数为 [2,0,0]。 | pending 优先，failed 按最后尝试时间轮转，保留执行器依赖排序与退避。修后新任务上传 1，重试计数 [1,1,0]。 | PR #15 |
| UI-01 | Medium | 首次加载中选择皮肤会覆盖原图标；保存失败后重复选同项不能重试；慢写入与快速选择可能倒序持久化。 | 等初次读取、合并单字段、按顺序保存，失败恢复最近成功偏好且不覆盖更新的乐观选择。3 项改前全部失败，改后通过。 | PR #13 |
| UI-02 | Medium | 320px/390px 七日课表中，同日重叠课程强制最小 24px，覆盖相邻课程或跨入下一日。 | 宽度服从真实 lane，不改时间块高度或 00–24 时轴。真实 CalendarWorkspace 在两种宽度下验证课程互不覆盖且留在本日。 | PR #13 |
| BUILD-01 | High，静态 | 干净检出没有被忽略的 key.properties 时，Gradle 在配置 release 签名时 null as String；debug 配置也会经过该代码。 | 签名字段使用可空属性读取；release 仍使用独立 release 配置，缺私钥不能完成 release 签名。APK 实际构建仍因 SDK 缺失 BLOCKED。 | PR #13 |
| PLAN-01 | Medium | 已订阅计划页面后完成/取消任务或修改周期，planRecords 不变，页面不再汇总进度。 | 监听汇总读取的六张表。两个持续订阅回归覆盖 0→100→0% 和周期变更；改前均等待更新超时，改后通过。 | PR #16 |

## 外观偏好与兼容性

题述“外观偏好被同步误上传、覆盖或清理”在当前可见代码中未复现：appearance 保存不入同步队列；bootstrap 仅枚举 reminder-defaults:当前用户；下载只接受 reminder_defaults；离线合并不修改 AppSettings。新增同步回归覆盖未知外观更新/删除、提醒偏好删除、跨账号 bootstrap 及离线合并，设备外观保持不变。

修复保持 Course、Task、TimerSession、Check-in 的区分，不把结束计时改成自动完成。同步删除移除的是云端已删除事实的本机缓存，墓碑仍阻止旧快照复活。历史跨账号父子关联会明确拒绝恢复/合并，需要人工对照；不会自动改写其他账号的数据归属。分页继续沿用多请求快照语义，没有增加跨表服务端快照协议。

PNG/ICO/ICNS 九个图标资源均存在；本地 file_picker 依赖的 Windows saveFile(bytes) 实现会写文件，未重复写入。滚动标题已有减少动态效果和 TickerMode 保护。UI Widget 验证覆盖 320px、390px、1280px，以及更小日格/双倍文字缩放、底部导航与桌面 Sidebar；这些不替代 Android 真机视觉验收。

## 真实验证结果

工具链：Flutter 3.47.9 stable（c197ca5199）、Dart 3.13.7。复用项目已有依赖配置，不修改 pubspec 或 lockfile。完整原始命令结果保存在相邻证据目录，已去除本机绝对工作区路径并规范行尾空白，未改变命令结果。

| 命令/范围 | 结果 | 退出码与证据 |
| --- | --- | --- |
| 基准 main：flutter test --no-pub --reporter expanded | PASS，重新运行 323 项 | 0，[基准日志](2026-11-23/baseline-tests.txt) |
| 组合代码：flutter test --no-pub --reporter expanded | PASS，364 项，新增 41 项 | 0，[完整日志](2026-11-23/final-tests.txt) |
| dart analyze lib test tools/ui_preview.dart | WARN，57 条 warning/info，0 error；与基准忽略行号后逐条相同 | 2，[当前分析](2026-11-23/final-analysis.txt)、[基准分析](2026-11-23/baseline-analysis.txt)。没有标记为静态分析全绿。 |
| flutter build apk --debug --no-pub | BLOCKED，本机缺 Android SDK，未到 Gradle 配置/编译阶段 | 1，[APK 日志](2026-11-23/final-apk.txt) |
| flutter build web --no-pub --no-wasm-dry-run | PASS，生产 JS Web 构建 | 0，[Web 日志](2026-11-23/final-web.txt) |
| 四个独立分支定向测试 | PASS，UI 20、账号 39、同步 66、计划 4 | 均为 0，见 [UI](2026-11-23/independent-ui.txt)、[账号](2026-11-23/independent-accounts.txt)、[同步](2026-11-23/independent-sync.txt)、[计划](2026-11-23/independent-plans.txt) |
| 补丁与独立代码复核 | git diff --check PASS；独立复核未发现本轮新引入阻断 | 仅代码与本地回归结论 |

改前失败证据：[8 个归属入口](2026-11-23/isolation-before.txt)、[外观竞态](2026-11-23/appearance-before.txt)、[重叠课表](2026-11-23/overlap-before.txt)、[计划订阅](2026-11-23/plans-before.txt)、[队列饥饿](2026-11-23/sync-queue-before.txt)、[离线合并第三账号关联](2026-11-23/sync-merge-before.txt)。

测试维护说明：最初 Auth 同步健康测试未保持 Riverpod StreamProvider 活跃订阅，已修正测试监听后通过；最初分页 Mock 漏填 response.request，已修正 fixture。两者最初的测试设施错误不计作产品缺陷；分页产品证据来自现测试中旧单次查询 2/5 行和新 reader 完整 5/5 行的对照。

## 未修复与待核验

| 项目 | 状态/优先级 | 原因及下一步 |
| --- | --- | --- |
| Android APK、真机与原生 OCR/通知 | BLOCKED | 缺 Android SDK 与设备。本轮未安装工具链、未改系统设置；需具备工具链的环境执行构建及真机回归。不能把 Web/Widget PASS 当作原生通过。 |
| 真实登录、线上 RLS、恢复/上传 | BLOCKED | 仅核对仓库与模拟服务；未访问生产凭据/用户。需在测试环境验证 A/B 账号、会话过期、离线合并、限行和冲突。 |
| WorkBuddy/MCP/OAuth 与 M0 本地版本 | BLOCKED | 当前 Git 跟踪文件只有计划文档，无可见 server/services/integrations 服务实现。`docs/superpowers/plans/2026-10-28-checkd-m0-api.md` 标明拟建协议和服务路径 BLOCKED，M1 文档也说明仓库无现成 WorkBuddy 代码。需对照 M0 未推送实现及部署；不能声称已验证接口兼容。 |
| 桌面独立小窗账号边界 | High 候选，待双 engine 实机复现 | `main.dart` 根据启动参数固定小窗 owner，主窗退出/切账号没有可见的关闭或重新绑定 IPC。可能继续显示/操作 A 数据。本轮不贸然改 IPC；完成前不建议在共享设备上进行含真实数据的多账号小窗测试。 |
| Course/Template 子表订阅 | Medium 候选，待复现 | watchCourses/watchCourse 只订阅父表，规则另行 get，可能只改规则后旧订阅不刷新。未借 Plan 修复扩展未复现行为，后续补持续订阅测试。 |
| ReviewSnapshot 临时计时口径 | 待 M0 确认 | 当前复盘只聚合任务 TimerSession，不含临时计时。若该字段应代表全部主动专注，则存在漏计；本轮不擅自改口径。 |
| 遗留云 OCR Responses 文本解析 | Medium，静态确认，未修复 | 函数直接 fetch HTTP 后只读顶层 output_text；标准 HTTP 文本在 output[].content[] 内。当前默认入口仅本地 OCR，不影响已验证默认路径。需结合 M0 云端路线确认后单独修复并验证部署鉴权、配额。 |
| 统计月热力图硬编码色 | Low，未修复 | time_distribution_chart.dart 前三档固定粉色，最高档随主题改变，蓝/黄主题梯度不统一。其余 10 文件 27 处十六进制色多为中性轨道、高光/阴影。本轮未作无关全页重构。 |

## 内部联合测试建议

建议 M0 分别审核四个修复 PR，并在合并后的测试分支重跑全部命令。可以先用合成数据开展受控 Web/Widget 回归；在 Android 构建、真实 Auth/RLS、M0 本地服务对照及桌面小窗边界未补证前，不建议宣布全平台/多账号联合测试就绪。发现的本地隔离和恢复完整性风险已于本日回复任务邮件提前通报，未等完整报告。

## 参考依据

- [Supabase Dart select](https://supabase.com/docs/reference/dart/select)：默认限行与 range 分页；本修复也测试了低于默认值的服务端上限。
- [Responses HTTP reference](https://developers.openai.com/api/reference/resources/responses/methods/retrieve) 与 [Responses 迁移说明](https://developers.openai.com/api/docs/guides/migrate-to-responses)：用于核对遗留云 OCR 的 HTTP 结构和 SDK 文本 helper 差异。
