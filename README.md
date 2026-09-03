# Check D

跨平台个人任务打卡与时间记录 App，使用 Flutter 构建，目标平台为 iOS、Android、macOS 和 Windows。

## 当前阶段

Phase 1 基础架构、Phase 2 任务核心、Phase 3 计时系统、Phase 4 日历、Phase 5 标签统计与 Phase 6 计划：

- 响应式移动端底部导航与桌面端侧边栏
- Supabase 登录注册和离线体验入口
- Drift 本地数据库
- 本地优先同步队列骨架
- Supabase PostgreSQL schema、RLS 和迁移
- 周期任务与单次事项创建、编辑、详情和归档
- 周期任务和单次事项均可选择计时或不计时；计时可选目标时长
- 手动完成、目标达成与计时状态相互独立
- 每天、工作日、周末和自定义星期周期
- 任务颜色、计时目标预配置和全部任务管理
- 可靠的开始、暂停、继续与结束计时流程
- 多段 Timer Session、每日累计和独立的目标达成记录
- 后台恢复、跨午夜拆分和实时今日计时时长
- 月日历、任务颜色标记和每日完成度
- 当天周期任务、单次事项、计时时长与部分进度详情
- 手机日期详情页面与桌面端日历/详情并排布局
- 可自定义任务图案，并在任务卡片、详情与历史记录中统一展示

- 标签新建、重命名、颜色修改、归档与恢复，保留变更历史
- 所有计时模式均可选择标签，每段 Session 固化当时标签，未选择的归入「其它」
- 日/周/月/年时间分布、标签占比、周期任务完成率和目标达成次数
- 各任务累计成功天数、当前连续和历史最长连续天数
- 任务详情展示周期目标剩余天数及周/月/年完成率，日历当天详情展示标签时间
- 依据任务修改历史还原旧周期，未来日期不进入本期完成率分母
- 月度/年度计划创建、编辑、归档与周期任务关联
- 计划根据关联周期任务的应执行次数与手动完成记录实时汇总进度

公开网页当前保持旧版本；后续 UI 重新设计并确认后再发布更新。

复盘功能将按照后续阶段逐步实现。节假日数据源、通知、云端同步执行器尚未启用；已有排除记录可参与统计过滤。当前浏览器数据按设备本地时区划分，固定账号时区及跨时区迁移留待同步阶段。

## 本地运行

1. 安装 Flutter stable，并执行 `flutter doctor`。
2. 运行 `flutter pub get`。
3. 运行 `dart run build_runner build`。
4. 使用 `flutter run -d macos` 或目标设备启动。

浏览器测试可运行：

```bash
flutter run -d chrome
```

Web 版使用 `web/sqlite3.wasm` 与 `web/drift_worker.js` 在浏览器本地持久化离线数据。

未配置 Supabase 时可以使用离线体验模式。启用云端登录时通过 `dart-define` 传入：

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-publishable-key
```

数据库迁移位于 `supabase/migrations/`，密钥不得提交到 Git。
