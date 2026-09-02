# Check D

跨平台个人任务打卡与时间记录 App，使用 Flutter 构建，目标平台为 iOS、Android、macOS 和 Windows。

## 当前阶段

Phase 1 基础架构：

- 响应式移动端底部导航与桌面端侧边栏
- Supabase 登录注册和离线体验入口
- Drift 本地数据库
- 本地优先同步队列骨架
- Supabase PostgreSQL schema、RLS 和迁移

任务、计时、日历、统计、计划和复盘功能将按照项目阶段逐步实现。

## 本地运行

1. 安装 Flutter stable，并执行 `flutter doctor`。
2. 运行 `flutter pub get`。
3. 运行 `dart run build_runner build`。
4. 使用 `flutter run -d macos` 或目标设备启动。

未配置 Supabase 时可以使用离线体验模式。启用云端登录时通过 `dart-define` 传入：

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-publishable-key
```

数据库迁移位于 `supabase/migrations/`，密钥不得提交到 Git。
