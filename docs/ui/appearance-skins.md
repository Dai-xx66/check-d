# 外观、图标与日历显示审核说明

本次包含三套浅色皮肤、应用内图标与小羊插画，以及月历和课表的显示修正。一级导航仍为「今天、日历、统计、我的」，中央「＋」保持创建操作；课程、任务、计时与完成记录继续使用原有模型和数据逻辑。

## 皮肤与偏好

| 存储 id | 名称 | 视觉方向 |
|---|---|---|
| `lamb` | 小羊日常 | 暖白背景与粉色角色，保留四色强调 |
| `slate` | 雾蓝 | 珍珠白、浅雾蓝与半透明玻璃表面 |
| `neutral` | 素纸 | 暖白、奶油黄与半透明玻璃表面 |

入口为「我的 → 换皮肤 / 更换图标」。皮肤和图标可独立选择，使用 `AppSettings` 的 `appearance.skin`、`appearance.icon` 保存本机偏好，不参与云同步。

`AppSkin` 定义颜色令牌，`AppColors` 从运行时宿主读取，`AppTheme.build` 驱动主题更新。颜色 getter 不能用于 `const` 构造；页面应继续使用语义色并建立主题依赖。`GoRouter` 保存在 App 的 State 中，换肤时保持当前路由。

## 图标与页面插画

- 三套图标资源为 `assets/images/app_icon_lamb.*`、`app_icon_mist_d.*`、`app_icon_cream_d.*`，提供 PNG、ICO、ICNS，可在外观设置中导出。
- 蓝色小羊使用浅蓝头毛、较明显的暖米金双角、浅雾蓝身体与冰蓝腹部；黄色小羊使用奶油黄配色。两者均为 2D 手绘形式，双蹄直接抱住 D，字母旁有圆点点缀。
- 蓝、黄主题各有招手、看书、捧杯、记笔记、放松坐着、庆祝六种动作。装饰动作与语义状态分别选择，保持原来的计时和无障碍状态标签。
- 欢迎区小羊在桌面使用 108px、手机使用 84px；盆栽靠近脚边。日程卡和侧栏按留白放置书杯、枝叶等小摆件，装饰不接收点击、不参与朗读。

选择图标会即时更新应用内标识并保存偏好。系统启动器图标仍需各平台安装包和原生配置支持；本次不提供 Android/iOS 运行时启动器图标切换，也不自动替换 Windows/macOS 已安装程序的图标。

## 月历与课表

- 月历按扣除外边距后的实际空间布局，修复数字上沿裁切；紧凑格的日期与事项数量上下居中，星期标题使用相同列间距。宽格保留事项摘要。
- 手机课表继续展示 00:00–24:00 全日纵轴和七天列，课程块的纵向位置与高度仍对应课程安排时段。
- 窄课程块减少内距，优先按可用宽高测量多行课程名；仍放不下时，在原块内缓慢横向滚动，首尾停顿。短名称保持静止，减少动态效果设置停用滚动。
- 长按可查看完整名称；点击课程弹层展示全名、时间和教室，并保留单次修改与后续规则修改入口。

## 本地交互预览

`tools/ui_preview.dart` 使用独立的 `check_d_visual_review` 演示数据库和离线配置，不接入真实云端数据。演示数据包含周二、周四 10:30 的长课名课程，便于检查跑马灯。正式入口仍为 `lib/main.dart`。

在项目根目录运行以下 PowerShell 命令：

```powershell
flutter pub get
flutter build web -t tools/ui_preview.dart --output build/ui-review
New-Item -ItemType Directory -Force build/ui-review/review | Out-Null
Copy-Item design/ui-review/index.html build/ui-review/review/index.html
python -m http.server 4281 --bind 127.0.0.1 --directory build/ui-review
```

打开 `http://127.0.0.1:4281/review/`，可切换三套皮肤，以及 1440 × 1000 桌面和 390 × 844 手机布局。静态服务器须以 `build/ui-review` 为根目录，才能正确加载预览框架中的应用与资源。

## 审核图片与检查

- [桌面实景](../../design/ui-review/blue-lamb-body-desktop.jpg)、[手机实景](../../design/ui-review/blue-lamb-body-mobile.jpg)、[蓝色角色与图标](../../design/ui-review/blue-lamb-body-review.png)
- [雾蓝与奶油黄图标](../../design/ui-review/icons-overview.png)、[页面动作](../../design/ui-review/mascot-poses.png)
- [月历对齐前后](../../design/ui-review/calendar-alignment-before-after.jpg)、[课表标题前后](../../design/ui-review/timetable-before-after.jpg)；跑马灯请在交互预览中检查。

本次独立审核分支已运行完整测试：323 项通过，正式 Web 构建成功。相关检查命令：

```powershell
flutter test test/appearance_theme_test.dart test/theme_skin_test.dart test/check_d_design_system_test.dart
flutter test test/calendar_month_cell_test.dart test/calendar_week_event_block_test.dart test/calendar_timetable_density_test.dart test/widget_test.dart
flutter build web
```

视觉验收重点：两种宽度下的文字完整性、横向溢出、底部导航遮挡、切换皮肤后路由是否保留，以及长课名滚动、长按和课程弹层。

## 素材生成记录

图片使用指定的豆包 API 生成，并进行透明边裁切、尺寸归一与局部配色处理；记录中不包含密钥。

- [图标](../../design/ui-review/icon-prompts.md)、[六种动作](../../design/ui-review/mascot-prompts.md)、[日常摆件](../../design/ui-review/daily-props-prompts.md)
- [蓝色头毛与双角](../../design/ui-review/blue-lamb-v2-prompts.md)、[身体蓝色及小蹄局部统一](../../design/ui-review/blue-lamb-body-prompts.md)
