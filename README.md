# Check D

跨平台个人任务打卡与时间记录 App，使用 Flutter 构建，目标平台为 iOS、Android、macOS 和 Windows。

## 当前阶段

Phase 1 基础架构、Phase 2 任务核心、Phase 3 计时系统、Phase 4 日历、Phase 5 标签统计、Phase 6 计划与 Phase 7 复盘：

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
- 日、周、月、年复盘；保存客观完成/计时快照、自由文本与情绪

公开网页当前保持旧版本；后续 UI 重新设计并确认后再发布更新。

节假日数据源、通知、云端同步执行器尚未启用；已有排除记录可参与统计过滤。当前浏览器数据按设备本地时区划分，固定账号时区及跨时区迁移留待同步阶段。跨平台打包与签名要求见 [发布清单](docs/release-checklist.md)。

## 校赛交付物（M3）

大学生智能体应用大赛的验收与演示材料集中在以下位置，建议从本表进入：

| 产出 | 位置 | 说明 |
|---|---|---|
| 验收用例 | [docs/contest/acceptance-cases.md](docs/contest/acceptance-cases.md) | 三条必演示场景 + 13 条边界用例，附需求覆盖对照表 |
| 证据索引 | [docs/contest/evidence-index.md](docs/contest/evidence-index.md) | 90 项（9 场景 / 13 边界 / 15 拆解 / 23 契约 / 8 增量 / 2 第三轮 / 20 EX 回放）逐条登记运行日期、版本、命令、证据位置；结论须带证据级别 E0–E3，未测 70 项 |
| 初赛大纲 | [docs/contest/submission-outline.md](docs/contest/submission-outline.md) | ≤3 页骨架：需求价值 30 / 创新 25 / 技术 25 / 完成度 20，含填空位与提交前 8 项自检 |
| 验收矩阵 | [docs/contest/acceptance-matrix.md](docs/contest/acceptance-matrix.md) | 基准 `c53b1a9`：32 编号 / 33 项（T01–T22 + R1/X1/G1–G5/S1 + V1/Y1）四元组断言；§3C 改判表、§5 阻塞结算（B5–B18 解除，G5 残留）；可判 32 / 部分 1 / 不可判 0，零执行 |
| 契约机检脚本 | [tools/m3-checks/check_contract_consistency.py](tools/m3-checks/check_contract_consistency.py) | 静态比对正文枚举与示例，`python tools/m3-checks/check_contract_consistency.py 2c48579` → 越界 0 |
| 证据索引自检 | [tools/m3-checks/check_evidence_index.py](tools/m3-checks/check_evidence_index.py) | 88 行齐全、结果枚举合法、**非「未测」必须带 E0–E3 级别且有证据位置**；→ 703 项检查 0 失败 |
| EX 回放独立记录 | [docs/contest/ex-replay-evidence.md](docs/contest/ex-replay-evidence.md) | A 的 EX-01–EX-20 逐条独立复核：PASS 7 / 形状级 2 / 不可复核 10 / 不可执行 1（EX-17 已按 `c53b1a9` 改判可执行）；不转述 A 的 pass |
| M2 测试映射 | [docs/contest/m2-test-mapping.md](docs/contest/m2-test-mapping.md) | B 的 38 条调度测试 ↔ 矩阵用例静态映射（34 条可映射）；全部「自述、E0」，不构成背书 |
| EX 回放复核脚本 | [tools/m3-checks/verify_ex_replay.py](tools/m3-checks/verify_ex_replay.py) | 只读证据里的原始响应，用 C 的断言重判；读不到就记 UNVERIFIABLE，并用 UNBACKED 抓「声称零写入但无计数」 |
| 课表脱敏 | [tools/m3-checks/build_timetable_fixture.py](tools/m3-checks/build_timetable_fixture.py) | 真实课表 CSV → 去身份/教师教室占位 → `scenario_d_real_timetable.json`；`--demo` 可自测 |
| 提交预检 | [tools/m3-checks/preflight_submission.py](tools/m3-checks/preflight_submission.py) | 扫描提交材料：学校/学院名、姓名/学号、手机/邮箱、API 密钥、真实用户路径，10 条规则；顺带统计未填占位符 |
| 拆解质量用例 | [docs/contest/decomposition-acceptance.md](docs/contest/decomposition-acceptance.md) | DA01–DA15 六维判据（覆盖率/原子性/时长守恒/依赖有序/截止继承/写入安全），对应计划 D3；当前零执行 |
| 契约评审（M3） | [docs/reviews/](docs/reviews/) | 逐版只读评审与复核，最新为 [M0-1 固定基准 `2c48579` 增量对齐](docs/reviews/2026-10-31-c-incremental-alignment-2c48579.md)（含文件指纹与机检） |
| 演示脚本 | [docs/contest/demo-script.md](docs/contest/demo-script.md) | 现场演示的逐步操作与口播要点 |
| 界面走查 | [docs/contest/ui-review-checklist.md](docs/contest/ui-review-checklist.md) | 用词一致性、前后差异、失败态文案、390px 手机宽度，共 19 项；未执行 |
| 盲测包 | [docs/contest/blind-test-kit.md](docs/contest/blind-test-kit.md) | 给非开发者的 10 步操作单 + 观察记录表 + 判定规则；未执行 |
| 开源与合规披露 | [docs/contest/oss-disclosure.md](docs/contest/oss-disclosure.md) | 第三方依赖、许可证、数据来源与隐私边界 |
| 场景样本数据 | [fixtures/education/](fixtures/education/README.md) | 三条教育场景 JSON + 13 条边界用例 + 15 条拆解用例（DA），可脱敏、可复现 |
| 样本自检 | [validate_fixtures.py](fixtures/education/validate_fixtures.py) | `python validate_fixtures.py --privacy` 校验字段完整性与隐私 |
| 前后对比视觉稿 | [before-after-preview.html](docs/demo/before-after-preview.html) | 浏览器直接打开，可点击交互 |
| 端到端演练 | [docs/demo/e2e-playbook.md](docs/demo/e2e-playbook.md) | 环境准备、录制流程与失败兜底 |
| 评分证据映射 | [scoring-evidence-map.md](docs/submission/scoring-evidence-map.md) | 按官方 30/25/25/20 分值逐项对应证据 |
| 提交材料清单 | [materials-checklist.md](docs/submission/materials-checklist.md) | 待提交文件与状态跟踪 |

场景样本与真实代码存在字段偏差（计划文档的 `ScheduleBlock` 实际为 `DailyItemOverride`），细节见 [fixtures/education/README.md](fixtures/education/README.md) 与 [interface-notes-for-m0.md](docs/demo/interface-notes-for-m0.md)。

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
