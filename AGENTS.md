# AGENTS.md

本文件给 Codex/自动化开发代理读取。项目根目录是当前目录，即包含 `pubspec.yaml`、`.git`、`lib/`、`test/` 的这一层；不要把 `src`、`lib` 或平台目录当作项目根目录。

## 项目概况

这是一个 Flutter 跨平台个人任务打卡与时间记录 App，目标平台包括 macOS、Windows、iOS、Android，并提供 Web 版本用于测试。

当前产品核心是“大学生的一天”。一天由以下互相独立的概念组成：

- Course 课程
- 周期任务
- 单次事项
- Ad-hoc Timer 临时计时
- 计时记录
- 手动完成/打卡
- Daily Review 每日复盘
- 日历、统计与个人设置

必须严格区分计划日期、计划时间和实际发生时间。计划时间不能覆盖实际 TimerSession 或 Check-in 记录。

请统一使用「周期任务」「单次事项」命名，不要再使用「长期任务」「短期任务」等旧名称。
课程必须使用 `Course` 命名和独立模型，不能做成普通 `Task`。

## 代码结构

- `lib/app`: App 入口与全局组装
- `lib/core`: 数据库、主题、同步、通知、节假日等基础能力
- `lib/features/tasks`: 任务模型、仓库、创建/编辑/详情
- `lib/features/courses`: 课程、课程规则和作息模板
- `lib/features/schedule`: 单日例外、提醒规则、闹钟规则和当天日程底座
- `lib/features/today`: 今日页与今日聚合展示
- `lib/features/calendar`: 日历与日期详情
- `lib/features/statistics`: 统计与标签时间分析
- `lib/features/plans`: 月度/年度计划
- `lib/features/reviews`: 日/周/月/年复盘
- `lib/features/profile`: “我的”页面与各类设置入口
- `lib/features/tags`: 标签管理
- `lib/features/shell`: 响应式导航壳
- `lib/shared/widgets`: 可复用 UI 组件
- `supabase/migrations`: 云端数据库 schema 与 RLS 迁移
- `test`: Widget 和业务流程测试

## 开发原则

- 先阅读现有代码，再修改。
- 不要重建项目，不要大规模重构无关模块。
- 保持 UI、业务逻辑、数据库、状态管理分离。
- PC 和 Mobile 可以有不同 Layout，但必须共享 Task Model、Timer、Completion、Repository/Service 和统计逻辑。
- `Course`、`Task`、`TimerSession`、`Check-in` 不能混成一个概念。
- 临时修改某一天或某一节时，只能写入单日例外数据，不能污染后续周期规则。
- 计时状态和完成状态必须独立：
  - `timerStatus`: `idle` / `running` / `paused`
  - `completionStatus`: `pending` / `completed`
  - `targetReached` 只表示目标时长达到，不自动完成任务
- 不要写 `stopTimer() -> completeTask()` 之类的隐式完成逻辑。
- 所有任务名称必须校验非空，前端和数据层都要校验。
- 删除任务优先归档或软删除，避免丢失历史统计数据。
- 所有统计尽量从 TimerSession、Completion、Review 等原始记录计算。
- 课程只是日程状态，不属于主动 Timer，不属于打卡，不产生连续打卡，也不能混入主动专注时间和学习标签。
- 提醒系统必须区分到点提醒、提前提醒、闹钟模式。固定时间事项必须有到点提醒，提前提醒不能替代到点提醒。
- 平台能力通过 `PlatformCapabilities` 等抽象表达，不要假设 Android、iOS、Windows、macOS、Web 的通知/闹钟/锁屏/悬浮窗能力一致。

## 信息架构硬规则

- 移动端底部固定为：`今天 | 日历 | ＋ | 统计 | 我的`。
- 真正的一级页面只有 Today、Calendar、Statistics、My。
- 中央 `＋` 是创建 Action，不是 Tab；点击后保持当前页面为背景并打开创建 Sheet。
- 创建 Sheet 提供：添加课程、周期事项、单次事项、立即开始计时。
- “复盘”不是一级导航，也不能替代“我的”。今日复盘位于 Today 页面底部，通过 Bottom Sheet 打开。
- 桌面端使用相同的信息架构，通过 Sidebar 展示“今天、日历、统计、我的”，并将“添加”作为独立操作入口。
- `PlansPage`、`ReviewsPage` 及其数据层可以作为功能模块保留，但不能自行加入一级导航。

## UI 方向

当前视觉方向是“小羊日常四色轻玻璃风”：暖白背景、大圆角、极细边框、轻阴影、轻玻璃拟态和粉色小羊角色系统。

- 不要直接复制参考图或品牌素材。
- 可以使用项目内原创资产 `assets/images/pink_lamb_piano.png`。
- 强调色固定为四类：粉红用于主操作与今日进度；淡紫用于学习、成长与统计重点；淡蓝用于课程、日历与时间安排；淡绿用于健康、完成与积极反馈。
- 奶白、暖灰和深棕是中性色，不计入强调四色；避免整页高饱和粉色。
- 任务色只用于图标背景、进度条、状态点和左侧色线，不要大面积铺满任务卡片。
- 按钮使用半透明奶白或浅色玻璃底、细描边和轻阴影；主按钮可使用低饱和粉红到淡紫渐变，必须保证文字对比度。
- 保留既有功能结构，只做视觉迁移时不得改坏业务逻辑。
- 手机端不要直接压缩桌面布局，应使用独立移动端布局。
- 桌面端保持左侧 Sidebar 与 Dashboard 网格布局。
- 首页任务应聚合为 Section Card 内的紧凑任务行，不要每条任务都使用巨大卡片。
- 首页删除属于次要操作，应放入更多菜单，不要让垃圾桶图标长期占据主要视觉权重。

## 统计页规则

- Statistics 一级周期固定为：`周 | 月 | 学期 | 年`，默认周视图；不要增加“日”Tab。
- 周视图使用每日专注柱状图，月视图使用每日专注热力图，学期视图使用每周专注折线图，年视图使用每月专注柱状图。
- 标签专注分布使用环形图和真实标签数据，显示时长与占比。
- 统计只能来自主动计时事实记录：任务 `TimerSession` 与临时计时记录。课程时段不能计入专注时长、标签统计或打卡。
- 学期范围优先读取课程已有的学期名称和起止日期；缺失时可按自然学期推导，不为此改数据库。
- Desktop 使用四张摘要卡及“宽趋势图 + 窄标签环图”；Mobile 使用紧凑纵向布局，不得横向溢出。
- 空统计状态不显示无意义坐标轴，应显示紧凑说明、小羊和“开始计时”入口。

## 常用命令

```bash
flutter pub get
dart run build_runner build
flutter test
flutter test test/statistics_test.dart test/statistics_charts_test.dart
flutter build web
flutter build macos
```

浏览器本地测试可以使用：

```bash
flutter run -d chrome
```

或在 `build/web` 生成后用静态服务器预览。

## 注意事项

- 不要提交 Supabase 密钥或任何私密配置。
- Android SDK、Windows 构建、iOS 签名和 GitHub Push 只有在用户明确要求时再处理。
- 每完成一个明显阶段，先运行相关测试和构建，再总结变更。
- 工作区可能包含用户或前序阶段的未提交改动。不要重置、覆盖或清理与当前任务无关的修改。
- UI 验收至少覆盖桌面宽度和约 390px 手机宽度，检查文字截断、横向溢出、Bottom Navigation 遮挡和响应式切换。
