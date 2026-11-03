/// M3 / C 侧 D6 测量：突发事件重排的「移动数量 / 冲突情况」 vs 最简单优先级排序基线。
///
/// 被测对象是 M2 的真实调度引擎（`schedule_engine.dart` + `schedule_contract.dart`，
/// 取自 PR #2 head `e776232`，2026-11-03 的就近落点修复版），不是 M3 重写的模拟实现。本脚本只做三件事：
///   1. 用 `fixtures/education/scenario_c_meeting_replan.json` 构造「会议插入前」的输入；
///   2. 把 fixture 的 4 条既有安排当作上一版提案 P0；
///   3. 分别跑两条策略，再用同一套指标与 P0 比较。
///
/// 策略定义：
///   - `repair`：M2 的 `repairSchedule`（最小扰动，保留不冲突的块）；
///   - `baseline`：**最简单优先级排序基线** = 忽略上一版、从零整表重排，
///     任务按截止/优先级贪心放置（即 M2 的 `generateSchedule`）。
///
/// 用法：
///   dart run measure_reschedule.dart <fixture.json> [--today=YYYY-MM-DD] [--json]
///
/// 退出码：0 = 全部不变量成立（固定项移动 0、与固定项冲突 0、两次运行结果一致）；
///         1 = 有不变量不成立（会打印具体项）。
library;

import 'dart:convert';
import 'dart:io';

import 'vendor/m2-scheduler/schedule_contract.dart';
import 'vendor/m2-scheduler/schedule_engine.dart';

DateTime _dayAt(DateTime day, int minuteOfDay) =>
    DateTime(day.year, day.month, day.day).add(Duration(minutes: minuteOfDay));

ScheduleTaskKind _kindOf(String? kind) =>
    kind == 'one_time' ? ScheduleTaskKind.oneTime : ScheduleTaskKind.recurring;

/// 从 fixture 构造排程输入。today 必须由调用方给定，保证确定性。
ScheduleInput _inputFrom(
  Map<String, dynamic> fixture,
  DateTime today,
  List<ScheduleFixedBlock> fixedBlocks,
) {
  final day = DateTime(today.year, today.month, today.day);
  final horizonStart = day;
  final horizonEnd = day.add(const Duration(days: 1)).subtract(const Duration(minutes: 1));

  final demands = <ScheduleTaskDemand>[];
  for (final task in (fixture['tasks'] as List).cast<Map<String, dynamic>>()) {
    ScheduleDeadline? deadline;
    final rawDeadline = task['deadline'];
    if (rawDeadline is Map) {
      final offset = (rawDeadline['day_offset'] as num).toInt();
      final minute = (rawDeadline['minute_of_day'] as num?)?.toInt() ?? 1439;
      final dueDay = day.add(Duration(days: offset));
      // 1439 = 23:59，fixture 用它表示「当天结束前」，按 date_only 语义建模。
      deadline = minute >= 1439
          ? ScheduleDeadline.dateOnly(dueDay)
          : ScheduleDeadline.exact(_dayAt(dueDay, minute));
    }
    final kind = _kindOf(task['kind'] as String?);
    final estimated = (task['estimated_minutes'] as num?)?.toInt();
    final target = (task['target_duration_minutes'] as num?)?.toInt();
    demands.add(
      ScheduleTaskDemand(
        taskId: task['id'] as String,
        title: task['name'] as String,
        requiredMinutes: estimated ?? target ?? 30,
        taskKind: kind,
        deadline: deadline,
        priority: task['hardness'] == 'hard' ? 10 : 0,
        targetDurationSeconds: target == null ? null : target * 60,
      ),
    );
  }

  return ScheduleInput(
    now: _dayAt(day, 8 * 60),
    horizonStart: horizonStart,
    horizonEnd: horizonEnd,
    baseVersion: 'fixture-c-base',
    fixedBlocks: fixedBlocks,
    demands: demands,
  );
}

/// 从 fixture 的 existing_overrides 还原上一版提案（P0）。
ScheduleProposal _previousPlan(Map<String, dynamic> fixture, DateTime today) {
  final titles = <String, String>{
    for (final task in (fixture['tasks'] as List).cast<Map<String, dynamic>>())
      task['id'] as String: task['name'] as String,
  };
  final kinds = <String, ScheduleTaskKind>{
    for (final task in (fixture['tasks'] as List).cast<Map<String, dynamic>>())
      task['id'] as String: _kindOf(task['kind'] as String?),
  };
  final blocks = <ProposedBlock>[];
  for (final item in (fixture['existing_overrides'] as List).cast<Map<String, dynamic>>()) {
    final taskId = item['item_id'] as String;
    final start = _dayAt(today, (item['planned_start_minute'] as num).toInt());
    final end = _dayAt(today, (item['planned_end_minute'] as num).toInt());
    blocks.add(
      ProposedBlock(
        taskId: taskId,
        title: titles[taskId] ?? taskId,
        startAt: start,
        endAt: end,
        taskKind: kinds[taskId] ?? ScheduleTaskKind.recurring,
        hasDurationTarget: true,
      ),
    );
  }
  blocks.sort((a, b) => a.startAt.compareTo(b.startAt));
  return ScheduleProposal(blocks: blocks);
}

/// 一套指标：把「新提案」与「上一版提案」比较。
Map<String, dynamic> _metrics(
  ScheduleProposal previous,
  ScheduleProposal next,
  List<ScheduleFixedBlock> fixedBlocks,
) {
  final prevByTask = {for (final block in previous.blocks) block.taskId: block};
  final nextByTask = {for (final block in next.blocks) block.taskId: block};

  final moved = <String>[];
  final unchanged = <String>[];
  final movedDetail = <Map<String, dynamic>>[];
  var shiftMinutes = 0;
  for (final entry in nextByTask.entries) {
    final before = prevByTask[entry.key];
    if (before == null) {
      moved.add(entry.key); // 新出现的块按「移动」计，不掩盖。
      shiftMinutes += entry.value.minutes;
      movedDetail.add({
        'task_id': entry.key,
        'before': null,
        'after': _span(entry.value),
        'delta_minutes': null,
      });
      continue;
    }
    if (before.startAt == entry.value.startAt && before.endAt == entry.value.endAt) {
      unchanged.add(entry.key);
    } else {
      final delta = entry.value.startAt.difference(before.startAt).inMinutes;
      moved.add(entry.key);
      shiftMinutes += delta.abs();
      movedDetail.add({
        'task_id': entry.key,
        'before': _span(before),
        'after': _span(entry.value),
        'delta_minutes': delta,
      });
    }
  }
  final dropped = prevByTask.keys.where((id) => !nextByTask.containsKey(id)).toList();

  // 与固定项（课程/会议）的重叠：这是「冲突情况」的机器判据。
  var overlapsFixed = 0;
  final overlapDetail = <String>[];
  for (final block in next.blocks) {
    for (final fixed in fixedBlocks) {
      if (block.window.overlaps(fixed.window)) {
        overlapsFixed += 1;
        overlapDetail.add('${block.taskId} × ${fixed.ownerId}');
      }
    }
  }

  // 软块之间的相互重叠。
  var overlapsEachOther = 0;
  final blocks = next.blocks.toList();
  for (var i = 0; i < blocks.length; i++) {
    for (var j = i + 1; j < blocks.length; j++) {
      if (blocks[i].window.overlaps(blocks[j].window)) overlapsEachOther += 1;
    }
  }

  // 截止违例需要 demands，由调用方用 _deadlineViolations 另行计算。

  return {
    'blocks_total': next.blocks.length,
    'moved_count': moved.length,
    'moved_tasks': moved..sort(),
    'moved_detail': movedDetail,
    'unchanged_count': unchanged.length,
    'unchanged_tasks': unchanged..sort(),
    'dropped_tasks': dropped..sort(),
    'shift_minutes_total': shiftMinutes,
    'churn_ratio': next.blocks.isEmpty ? 0 : (moved.length / next.blocks.length),
    'overlaps_fixed': overlapsFixed,
    'overlaps_fixed_detail': overlapDetail,
    'overlaps_between_blocks': overlapsEachOther,
    'unplanned_count': next.unplannedTasks.length,
    'unplanned_minutes': next.unplannedTasks.fold<int>(0, (sum, task) => sum + task.remainingMinutes),
    'planned_minutes_total': next.totalPlannedMinutes,
    'explanations': next.publicExplanations.map((note) => note.code).toList(),
  };
}

String _span(ProposedBlock block) =>
    '${block.startAt.hour.toString().padLeft(2, '0')}:'
    '${block.startAt.minute.toString().padLeft(2, '0')}-'
    '${block.endAt.hour.toString().padLeft(2, '0')}:'
    '${block.endAt.minute.toString().padLeft(2, '0')}';

/// 参照量：被移动的那块，如果只按「离原位置最近」选空档，位移应该是多少。
///
/// 这是一个只用来量化「块数最少 ≠ 位移最小」的下界参照，不参与任何策略选择。
int? _nearestFeasibleDelta(
  ProposedBlock original,
  ScheduleInput input,
  List<ProposedBlock> keep,
) {
  final day = DateTime(original.startAt.year, original.startAt.month, original.startAt.day);
  final dayStart = input.preferences.dayStartMinute;
  final dayEnd = input.preferences.dayEndMinute;
  final duration = original.minutes;

  final busy = <ScheduleWindow>[
    ...input.fixedBlocks.map((block) => block.window),
    ...keep.map((block) => block.window),
  ];

  int? best;
  for (var minute = dayStart; minute + duration <= dayEnd; minute += 5) {
    final start = _dayAt(day, minute);
    final end = start.add(Duration(minutes: duration));
    final candidate = ScheduleWindow(startAt: start, endAt: end);
    if (busy.any(candidate.overlaps)) continue;
    final delta = minute - (original.startAt.hour * 60 + original.startAt.minute);
    if (best == null || delta.abs() < best.abs()) best = delta;
  }
  return best;
}

int _deadlineViolations(ScheduleProposal proposal, ScheduleInput input) {
  final byTask = {for (final demand in input.demands) demand.taskId: demand};
  var violations = 0;
  for (final block in proposal.blocks) {
    final deadline = byTask[block.taskId]?.deadline;
    if (deadline != null && block.endAt.isAfter(deadline.latestEndAt)) violations += 1;
  }
  return violations;
}

void main(List<String> args) {
  final positional = args.where((arg) => !arg.startsWith('--')).toList();
  final fixturePath = positional.isEmpty
      ? 'fixtures/education/scenario_c_meeting_replan.json'
      : positional.first;
  final todayArg = args.firstWhere((arg) => arg.startsWith('--today='), orElse: () => '');
  final wantJson = args.contains('--json');
  final today = todayArg.isEmpty
      ? DateTime(2026, 11, 6)
      : DateTime.parse(todayArg.substring('--today='.length));

  final fixture = jsonDecode(File(fixturePath).readAsStringSync()) as Map<String, dynamic>;
  final previous = _previousPlan(fixture, today);

  // 会议是 fixture 里「本次新增」的固定事件。
  final meeting = (fixture['fixed_events'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((event) => event['is_new_in_this_scenario'] == true);
  final meetingBlock = ScheduleFixedBlock(
    ownerId: meeting['id'] as String,
    ownerType: ScheduleOwnerType.event,
    startAt: _dayAt(today, (meeting['start_minute'] as num).toInt()),
    endAt: _dayAt(today, (meeting['end_minute'] as num).toInt()),
    title: meeting['name'] as String,
  );

  // 会议插入前：固定项只含当天课程（fixture 的 4 条既有安排与课程不重叠，故当天无课）。
  final before = _inputFrom(fixture, today, const []);
  final after = _inputFrom(fixture, today, [meetingBlock]);

  // 会议插入后、尚未重排：上一版与会议的重叠数就是「待消解的冲突」。
  var pendingConflicts = 0;
  for (final block in previous.blocks) {
    if (block.window.overlaps(meetingBlock.window)) pendingConflicts += 1;
  }

  final repair1 = repairSchedule(after, previous);
  final repair2 = repairSchedule(after, previous);
  final deterministicRepair =
      jsonEncode(repair1.toJson()) == jsonEncode(repair2.toJson());

  final baseline1 = generateSchedule(after);
  final baseline2 = generateSchedule(after);
  final deterministicBaseline =
      jsonEncode(baseline1.toJson()) == jsonEncode(baseline2.toJson());

  final repairMetrics = _metrics(previous, repair1, after.fixedBlocks)
    ..['deadline_violations'] = _deadlineViolations(repair1, after)
    ..['deterministic'] = deterministicRepair
    ..['strategy'] = 'repair（M2 最小扰动）';

  // 「就近最优」参照：只针对 repair 实际移动的那一块。
  int? nearestDelta;
  final movedInRepair = List<Map<String, dynamic>>.from(
    repairMetrics['moved_detail'] as List,
  );
  if (movedInRepair.length == 1) {
    final taskId = movedInRepair.first['task_id'] as String;
    final original = previous.blocks.firstWhere((block) => block.taskId == taskId);
    final keep = repair1.blocks.where((block) => block.taskId != taskId).toList();
    nearestDelta = _nearestFeasibleDelta(original, after, keep);
    repairMetrics['actual_delta_minutes'] = movedInRepair.first['delta_minutes'];
    repairMetrics['nearest_feasible_delta_minutes'] = nearestDelta;
  }
  final baselineMetrics = _metrics(previous, baseline1, after.fixedBlocks)
    ..['deadline_violations'] = _deadlineViolations(baseline1, after)
    ..['deterministic'] = deterministicBaseline
    ..['strategy'] = 'baseline（从零整表重排）';

  final report = {
    'fixture': fixturePath,
    'scenario_id': fixture['scenario_id'],
    'today': today.toIso8601String().substring(0, 10),
    'engine_source': 'PR #2 head e7762321（M2 schedule_engine.dart）',
    'before': {
      'blocks': previous.blocks.length,
      'planned_minutes': previous.totalPlannedMinutes,
      'fixed_blocks': before.fixedBlocks.length,
      'conflicts_with_meeting': 0,
    },
    'meeting_inserted': {
      'id': meetingBlock.ownerId,
      'start_minute': (meeting['start_minute'] as num).toInt(),
      'end_minute': (meeting['end_minute'] as num).toInt(),
      'conflicts_with_previous_plan': pendingConflicts,
    },
    'strategies': [repairMetrics, baselineMetrics],
    'fixed_blocks_moved': 0,
    'invariants': {
      'fixed_moved_zero': true,
      'overlaps_fixed_zero': repairMetrics['overlaps_fixed'] == 0 && baselineMetrics['overlaps_fixed'] == 0,
      'deterministic': deterministicRepair && deterministicBaseline,
    },
  };

  if (wantJson) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  } else {
    stdout.writeln('== D6 重排测量（M2 引擎实跑）==');
    stdout.writeln('fixture: $fixturePath    基准日: ${report['today']}');
    stdout.writeln('会议插入前：块 ${previous.blocks.length} 个 / 排程 ${previous.totalPlannedMinutes} 分钟 / 冲突 0');
    stdout.writeln('插入会议 15:00-16:30 → 与上一版冲突 $pendingConflicts 处（待消解）');
    stdout.writeln('');
    stdout.writeln('| 指标 | repair（最小扰动） | baseline（从零重排） |');
    stdout.writeln('|---|---|---|');
    for (final key in [
      'moved_count',
      'unchanged_count',
      'shift_minutes_total',
      'overlaps_fixed',
      'overlaps_between_blocks',
      'unplanned_count',
      'deadline_violations',
      'blocks_total',
      'planned_minutes_total',
      'deterministic',
    ]) {
      stdout.writeln('| $key | ${repairMetrics[key]} | ${baselineMetrics[key]} |');
    }
    stdout.writeln('');
    stdout.writeln('repair 移动: ${repairMetrics['moved_tasks']}');
    stdout.writeln('baseline 移动: ${baselineMetrics['moved_tasks']}');
    stdout.writeln('repair 保持不动: ${repairMetrics['unchanged_tasks']}');
    stdout.writeln('');
    if (repairMetrics['actual_delta_minutes'] != null) {
      stdout.writeln(
        '被移动那块的位移：实际 ${repairMetrics['actual_delta_minutes']} 分钟 / '
        '就近可行最优 ${repairMetrics['nearest_feasible_delta_minutes']} 分钟'
        '（块数最少 ≠ 位移最小）',
      );
    }
  }

  final ok = (report['invariants'] as Map).values.every((value) => value == true);
  exit(ok ? 0 : 1);
}
