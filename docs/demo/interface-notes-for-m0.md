# M3 → M0 接口核对说明（10/29 契约冻结用）

> 提出人：M3（同学 C）· 2026-10-29 · 依据 `main@b7a16db` 只读审计
> 用途：今天的目标是「四人确认唯一接口协议 Version 1」。这份文件列出 M3 从数据侧发现的**接口与计划文档不一致之处**，以及 C 在 D1 之后需要 M0 提供的三样东西。
> 处理方式建议：M0 逐条确认后写进 `docs/contracts/agent-api-v1.md`，或明确驳回并说明理由。

---

## 一、必须修正：`ScheduleBlock` 在代码里不存在

计划文档 §2/§4 把「计划占用的时间块」称作 `ScheduleBlock`，并设计了 `generate_schedule` 返回「新增/移动时间块」。但真实代码中没有这个实体。

**真实实现（已核实）：**

| 概念 | 真实类型 / 字段 | 位置 |
|---|---|---|
| 某天某个任务占用 15:00-16:00 | `DailyItemOverride` + `action: DayOverrideAction.reschedule` + `plannedStartMinute` / `plannedEndMinute` | `lib/features/schedule/domain/day_schedule_models.dart:19-44,45-75` |
| 读取某天全部覆盖 | `DayScheduleRepository.loadOverridesForDate(DateTime date)` | `lib/features/schedule/data/day_schedule_repository.dart:43` |
| 写入/更新覆盖 | `saveDailyOverride(DailyItemOverrideDraft draft, {String? overrideId})` | 同上 `:57` |
| 现有调用范例 | 今日页「安排到今天」 | `lib/features/today/presentation/today_page.dart:989-1000` |
| 固定课程 | `Course` + `CourseScheduleRule(weekday, startsAtMinute, endsAtMinute, weekRuleType, startWeek...)` | `lib/features/courses/domain/course_models.dart:105-140` |

**对契约的三点影响：**

1. **`get_calendar_events` 必须返回三类来源并标硬度**，否则 M2 无法判断"哪些能动"：
   - 课程（`hard`，按 `weekday + startWeek/endWeek` 展开成当天实例）
   - 单次事项中带 `scheduledAt` 的（`hard`，如会议、面试）
   - `DailyItemOverride`（`soft`，可重排；`action=skip` 表示当天不做）
2. **`apply_approved_changes` 的写载体是 `saveDailyOverride`，且必须复用 `overrideId`。**
   同一任务同一天重复调用不带 `overrideId` 会**新增一行**而不是更新，直接导致 E08（重复批准）失败。这是幂等性的实现要点，建议写进契约的必填字段说明：`changes[].target_override_id`（无则新增）。
3. **没有"删除时间块"的接口。** 撤销一个排期只能 `action: skip` 或删除 override 行。M0 需确认删除是否安全（涉及提醒规则 `_syncOverrideReminder` 的级联），否则契约里不要提供"移除"操作，展示层也相应不出现删除按钮。

**M3 的诉求：** 接口名可以继续叫 `ScheduleBlock`（对外语义清晰），但**字段映射必须落到 override**，并在契约里注明"一个 ScheduleBlock ≡ 一条 DailyItemOverride"。否则 A/B 按文档开发会写不出能跑的代码。

---

## 二、M3 已经开始按真实模型组织数据

`fixtures/education/` 下的三条场景已经用真实字段语义描述（`minute_of_day`、`weekday 1-7`、`hardness`、`existing_overrides`），**没有使用 `ScheduleBlock` 这个词**。校验脚本已跑通 336 项检查。

这意味着：如果 M0 的契约与 fixture 字段冲突，改动成本最低的是契约（因为 fixture 已经和代码对齐）。建议 M0 直接以 fixture 的字段名为参考做命名。

---

## 三、M3 在 D1 之后需要的三样东西（按优先级）

### 1. 只读工具的 Mock 返回样例（最急，阻塞 C 的展示层联调）

`list_tasks` 与 `get_calendar_events` 各一份真实结构的 JSON 样例即可，C 用它来验证差异展示区的数据绑定。
**不涉及密钥**，M0 可以直接从测试库导一份脱敏数据。

### 2. 测试账号的 seed 方式

C 需要能反复重置同一份数据（演示前重跑）。三种可行方式，任选其一：

- `supabase/seed.sql` 本地脚本（最优，可版本化）
- 一个"导入测试场景"的内部入口（仅 debug 构建可见）
- 手工导入步骤文档（最差但可接受）

**关键要求：能 30 秒复位。** 否则每次彩排都要手工建数据，5 分钟演示必然超时。

### 3. CI 里加一个不依赖设备的 job

C 本机没有 Flutter SDK，`test/e2e/` 的 Dart 测试无法执行。建议 M0 在 `.github/workflows/` 加：

```yaml
- name: Validate education fixtures
  run: python fixtures/education/validate_fixtures.py --privacy
```

这一步**不需要 Flutter、不需要密钥、3 秒跑完**，可以作为所有 PR 的最低门槛。Dart 测试可以后补。

---

## 四、状态与回执

| 项 | 状态 |
|---|---|
| M3 已完成 | 3 场景 fixture + 13 条边界用例 + 校验脚本（336 项通过）+ 前后差异规格与视觉稿 + 演示脚本 |
| M3 阻塞 | Flutter 环境缺失（Dart 测试无法执行）；Mock 返回样例未提供；seed 方式未定 |
| 需 M0 回执 | 上面三条的影响 1/2/3 是否采纳；三条诉求的排期 |

**回执方式：** 在本文件末尾追加 `## M0 回执（日期）`，或直接在 GitHub Issue 打 `M0` `P1` 标签回复。C 会据此调整 fixture 与展示层。
