# E2E 用例台账（M3）

> 归属：M3（同学 C）· 更新：2026-10-29
> 数据源：`fixtures/education/` · 展示规格：`docs/demo/before-after-spec.md`

## 0. 当前状态：BLOCKED（环境原因）

| 项 | 状态 |
|---|---|
| 用例定义 | ✅ 已完成（3 场景 × 6 断言 + 13 条边界） |
| fixture 数据 | ✅ 已完成并通过自检（336 项检查 / 0 失败） |
| 自动执行 | ⛔ **本机未安装 Flutter SDK**，`flutter test` 无法运行 |
| 转 Dart 测试 | ⏳ 待 A 或 M0 在具备 Flutter 的机器 / CI 上落地 |

**这不是"没做"，是"做到能做的边界后如实暴露"。** 计划文档 §9 要求「阻塞超过 2 小时直接在群里发报错」，此处按此处理：
需要 M0 在 GitHub Actions 里加一个 job 跑 `flutter test`，或由 A 在他本机跑通后把结果贴回本文件第 4 节。

本地可立即执行的部分（不需要 Flutter）：

```bash
python fixtures/education/validate_fixtures.py --privacy
```

## 1. 用例矩阵

### 1.1 三条主场景（对应计划 §8 必演示场景）

| 用例 | fixture | 断言数 | 关键判定 |
|---|---|---|---|
| TC-A 学习计划 | `scenario_a_study_plan.json` | A1-A6 | 新增块不撞课、不撞会、批准前零写入、已排块不动 |
| TC-B 任务拆解 | `scenario_b_report_breakdown.json` | B1-B6 | 子任务 ≥4、时长合计=360、缺口 60 分钟明确报出 |
| TC-C 突发事件重排 | `scenario_c_meeting_replan.json` | C1-C6 | 硬块 0 移动、软块恰好移动 1 个、override 行数仍为 4 |

### 1.2 边界用例（13 条，计划要求 ≥10）

详见 `fixtures/education/boundary_cases.json`。摘要：

| ID | 用例 | 级别 | 一句话判定 |
|---|---|---|---|
| E01 | 空任务列表 | P1 | 不编造任务，返回空 + 询问 |
| E02 | 无任何空闲时间 | P0 | 明确说排不下，不硬塞 |
| E03 | 截止日期已过 | P1 | 提示超期，不排到过去 |
| E04 | 时间块跨零点 | P1 | 显式拆分，分钟数不越界 |
| E05 | 时区不一致 | P1 | 统一换算北京时间 |
| E06 | 会议撞固定课 | P0 | 不移动课程，要求用户决策 |
| E07 | 时长超过可用 | P1 | 报出未排量，不压缩子任务 |
| E08 | 重复批准同一提案 | P0 | 幂等，不产生重复 override |
| E09 | 审批后日历被改（版本冲突） | P0 | 拒绝应用，重新生成 |
| E10 | 登录失效 / 跨用户 | P0 | 401/403，不泄露他人数据 |
| E11 | 工具超时 | P0 | 明说失败，不编造、不宣称已保存 |
| E12 | LLM 提议移动固定课 | P0 | 拒绝，给替代方案 |
| E13 | 知识库提示注入 | P0 | 当作数据，不执行越权指令 |

## 2. 手工执行步骤（A 或 M0 在真实环境跑）

每条用例固定四步，缺一步结果不可采信：

1. **装载数据**：按 fixture 在测试账号里建课程、任务、会议、已有 override（或由 M0 提供 seed 脚本）。
2. **发提示词**：用 fixture 的 `prompt`，不要临场改词（改了就无法复现）。
3. **记录证据**：截图 + 工具调用日志（请求参数 / 返回体 / 耗时）+ 时间戳。
4. **对照断言**：逐条打 `PASS / FAIL`，FAIL 要写实际发生了什么。

> 采信规则（写进提交材料时用）：只认**真实运行**产生的截图与日志。任何"手动拼出来的界面图"都不算证据，这也是计划 §1 的硬性要求。

## 3. 结果登记表（每次跑完填写，不要留空）

| 日期 | 用例 | 环境 | 结果 | 证据链接/文件名 | 备注 |
|---|---|---|---|---|---|
| 2026-10-29 | TC-A | _待填_ | _待填_ | | fixture 已就绪 |
| 2026-10-29 | TC-B | _待填_ | _待填_ | | |
| 2026-10-29 | TC-C | _待填_ | _待填_ | | |
| | E01–E13 | | | | 建议按 P0 优先 |

## 4. 转成 Dart 测试的指引（给 A / M0）

Flutter 项目的测试必须放在 `test/` 下才能被 `flutter test` 自动发现。当前目录 `test/e2e/` 下放 `.dart` 文件即可被扫描到（无需改 CI）。

建议落法：

```dart
// test/e2e/fixtures_load_test.dart
// 1) 读 fixtures/education/*.json，断言解析成功、字段完备
// 2) 用 DailyItemOverrideDraft / CourseScheduleRule 构造对象，验证字段映射
// 3) 纯 Dart 断言（冲突检测、时长合计），不需要 UI，跑得很快
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scenario C: 恰好一个软块与新增会议重叠', () {
    final data = jsonDecode(File('fixtures/education/scenario_c_meeting_replan.json')
        .readAsStringSync()) as Map<String, dynamic>;
    // ... 复用 validate_fixtures.py 中的同一套判定逻辑
  });
}
```

**注意**：当前仓库**没有任何 `.dart` 测试文件由 M3 编写**。我不虚构一个未经编译验证的测试文件塞进 `test/`，因为那会污染 CI 并制造"看起来跑了其实没跑"的假象（违反本项目 AGENTS.md 的诚实性原则）。等环境就绪后按上面模板补，或用 `python fixtures/education/validate_fixtures.py` 作为过渡期唯一可信校验。
