# AGENTS.md

本文件给 Codex/自动化开发代理读取。项目根目录是当前目录，即包含 `pubspec.yaml`、`.git`、`lib/`、`test/` 的这一层；不要把 `src`、`lib` 或平台目录当作项目根目录。

## 项目概况

这是一个 Flutter 跨平台个人任务打卡与时间记录 App，目标平台包括 macOS、Windows、iOS、Android，并提供 Web 版本用于测试。

核心业务是：

- 周期任务
- 单次事项
- 计时记录
- 手动完成/打卡
- 日历、计划、统计、复盘

请统一使用「周期任务」「单次事项」命名，不要再使用「长期任务」「短期任务」等旧名称。

## 代码结构

- `lib/app`: App 入口与全局组装
- `lib/core`: 数据库、主题、同步、通知、节假日等基础能力
- `lib/features/tasks`: 任务模型、仓库、创建/编辑/详情
- `lib/features/today`: 今日页与今日聚合展示
- `lib/features/calendar`: 日历与日期详情
- `lib/features/statistics`: 统计与标签时间分析
- `lib/features/plans`: 月度/年度计划
- `lib/features/reviews`: 日/周/月/年复盘
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
- 计时状态和完成状态必须独立：
  - `timerStatus`: `idle` / `running` / `paused`
  - `completionStatus`: `pending` / `completed`
  - `targetReached` 只表示目标时长达到，不自动完成任务
- 不要写 `stopTimer() -> completeTask()` 之类的隐式完成逻辑。
- 所有任务名称必须校验非空，前端和数据层都要校验。
- 删除任务优先归档或软删除，避免丢失历史统计数据。
- 所有统计尽量从 TimerSession、Completion、Review 等原始记录计算。

## UI 方向

当前视觉方向是柔和粉色系、暖白背景、大圆角、轻阴影、玻璃拟态和粉色小羊角色系统。

- 不要直接复制参考图或品牌素材。
- 可以使用项目内原创资产 `assets/images/pink_lamb_piano.png`。
- 保留既有功能结构，只做视觉迁移时不得改坏业务逻辑。
- 手机端不要直接压缩桌面布局，应使用独立移动端布局。
- 桌面端保持左侧 Sidebar 与 Dashboard 网格布局。

## 常用命令

```bash
flutter pub get
dart run build_runner build
flutter test test/statistics_widget_test.dart test/task_flow_widget_test.dart
flutter build web
flutter build macos --debug
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
