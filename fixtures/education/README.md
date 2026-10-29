# 教育场景样本（M3 / 同学 C）

> 用途：为 WorkBuddy Agent 的三条必演示场景提供**可复现、可脱敏、与真实模型对齐**的输入数据。
> 归属模块：M3。目录所有权：`fixtures/education/`。
> 版本：v1.0 · 2026-10-29

---

## 1. 三条场景与文件

| 文件 | 场景 | 对应计划文档 §8 必演示场景 |
|---|---|---|
| `scenario_a_study_plan.json` | 查看明天任务与课程，把英语复习排进空闲时间 | ① 学习计划 |
| `scenario_b_report_breakdown.json` | 周五前完成科研报告，拆成子任务并分配时间 | ② 复杂任务拆解 |
| `scenario_c_meeting_replan.json` | 下午插入固定会议，尽量少改其他安排 | ③ 突发事件重排 |
| `boundary_cases.json` | 13 条边界/异常用例（≥10 条要求） | §8 必测边界 |

## 2. 重要：与计划文档的字段偏差（必须让 M0/M1/M2 知道）

计划文档 §4 写的 `ScheduleBlock` 在 **CheckD 真实代码中不存在**。核对结果（2026-10-29，基于 `main@b7a16db`）：

| 计划文档概念 | 真实实现 | 证据 |
|---|---|---|
| `ScheduleBlock`（计划占用的时间块） | `DailyItemOverride` + `DayOverrideAction.reschedule` + `plannedStartMinute/plannedEndMinute` | `lib/features/schedule/domain/day_schedule_models.dart:19-44`、`lib/features/today/presentation/today_page.dart:989-1000` |
| 任务 | `Task`（`TaskKind.recurring` / `TaskKind.oneTime`） | `lib/features/tasks/domain/task_models.dart:1-3` |
| 固定课程 | `Course` + `CourseScheduleRule`（weekday + `startsAtMinute`） | `lib/features/courses/domain/course_models.dart:105-140` |
| 读取某天计划 | `dayScheduleRepository.loadOverridesForDate(date)` | `lib/features/schedule/data/day_schedule_repository.dart:43` |
| 写入某天计划 | `dayScheduleRepository.saveDailyOverride(draft, overrideId:)` | 同上 `:57` |

**这对 M0 的直接影响：**
1. 只读工具 `get_calendar_events` 必须返回**三类**来源并区分硬/软：课程规则（硬）、带 `scheduledAt` 的单次事项（硬）、`DailyItemOverride`（软，可重排）。
2. 写入工具 `apply_approved_changes` 的实现载体是 `saveDailyOverride`，**必须传已有 `overrideId` 表示更新**，否则重复批准会产生多条覆盖记录。这天然满足幂等要求，但需要 M0 在契约里写清楚。
3. 不存在"删除时间块"的接口。撤销一个已排的时间块只能是 `action: skip` 或删除 override，M0 需确认能否安全删除。

详见 `docs/demo/interface-notes-for-m0.md`。

## 3. 时间表达约定

- 时区：统一 `Asia/Shanghai`（UTC+8）。绝对值时间用带偏移的 ISO 8601，如 `2026-10-30T19:00:00+08:00`。
- 星期：`1=周一 … 7=周日`，与 Dart `DateTime.monday == 1` 一致。
- 分钟：`minute_of_day` 为当天 0 点起的分钟数，`08:00 → 480`、`23:59 → 1439`。与 `CourseScheduleRule.startsAtMinute`、`DailyItemOverride.plannedStartMinute` 一致。
- 日期：一律用 `day_offset`（相对 anchor 的偏移，0=今天，1=明天），**不写死具体日期**，保证任何一天演示都成立。`time.resolve.py` 不需要——直接按 offset 计算即可。

## 4. 硬约束与软约束

每个时间项带 `hardness` 字段，取值：

- `hard`：不可移动。课程（`CourseScheduleRule`）、带 `scheduledAt` 且 `remind_mode=due` 的单次事项（如会议、面试、考试）。
- `soft`：可被重排。周期任务的计划时间、无 `scheduledAt` 的单次事项。

**判定规则（M2 调度器必须遵守）：** 任何 `hard` 项的位置在整个提案中不得变化；`soft` 项移动必须给出理由，并计入 `moved_blocks`。

## 5. 场景数据是虚构的

所有姓名、课程名、教师、教室、学号均为构造数据：

- 姓名统一使用「学生A / 学生B」等占位；课程使用通用课名（高等数学、大学英语、数据结构）。
- 不含真实院校、真实教师姓名、真实学号、真实手机号。
- `fixtures/education/` 下所有文件通过 `validate_fixtures.py --privacy` 的 PII 扫描（11 位手机号、身份证号、邮箱、学号格式）。

## 6. 自检脚本

```bash
# 结构与约束校验 + 隐私扫描
python fixtures/education/validate_fixtures.py --privacy

# 只校验某一个场景
python fixtures/education/validate_fixtures.py --scenario A
```

退出码 `0` 表示通过；非 0 时逐条打印失败项。CI 可在 M0 配置好 workflow 后挂上这一步（不依赖 Flutter）。

> 本机当前**未安装 Flutter SDK**，因此 Dart 侧的 `test/e2e/` 无法在本地执行。
> `test/e2e/` 目前放的是可执行用例清单（`cases.md` + JSON），等 A/M0 环境就绪后由 A 转为 Dart 测试或由 M0 在 CI 跑。这一点已在 `docs/demo/interface-notes-for-m0.md` 标注为 BLOCKED。

## 7. 场景验收（对应 DoD）

| 场景 | 通过标准 |
|---|---|
| A 学习计划 | 读到 ≥3 条明日事项；提案新增块落在空闲区间且不与课程/会议重叠；批准前 `write_count = 0` |
| B 任务拆解 | 输出结构化子任务 ≥4 条且时长合计 = 任务预估；不可排部分明确列为 `unplanned_tasks` |
| C 突发事件重排 | 固定项 `moved_hard_blocks = 0`；只移动与会议重叠的软块（本数据为 1 块），其余保持不变 |
