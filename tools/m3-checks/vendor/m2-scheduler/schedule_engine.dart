/// M2 智能调度引擎：确定性、可解释、零数据库访问。
///
/// 两个入口：
/// - [generateSchedule]：从零排出一版提案。
/// - [repairSchedule]：硬约束发生变化后做最小扰动重排。
///
/// 实现纪律：
/// - 不 import 任何 repository、drift 或 UI 文件，因此可以被单独测试。
/// - 不调用 `DateTime.now()`，时间基准全部来自 [ScheduleInput.now]，
///   否则「相同输入相同输出」这条验收就无法成立。
/// - 绝不移动 [ScheduleFixedBlock]。硬约束冲突只会被记录和避开。
/// - 只产出提案，不产生任何写入动作。
library;

import 'schedule_contract.dart';

bool _atOrBefore(DateTime a, DateTime b) =>
    a.isBefore(b) || a.isAtSameMomentAs(b);

bool _atOrAfter(DateTime a, DateTime b) => a.isAfter(b) || a.isAtSameMomentAs(b);

DateTime _later(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

DateTime _earlier(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

int _compareWindows(ScheduleWindow a, ScheduleWindow b) {
  final start = a.startAt.compareTo(b.startAt);
  if (start != 0) return start;
  final end = a.endAt.compareTo(b.endAt);
  if (end != 0) return end;
  return 0;
}

/// 把可用窗口裁剪到排程区间内，并按本地日切分。
///
/// 切分之后每个窗口都属于同一个自然日，
/// 于是「任务块不得跨日」这条边界在使用窗口时就天然成立。
List<ScheduleWindow> _usableWindows(ScheduleInput input) {
  final earliest = _later(input.horizonStart, input.now);
  if (!input.horizonEnd.isAfter(earliest)) return const [];

  final clipped = <ScheduleWindow>[];
  for (final window in _effectiveAvailability(input)) {
    final start = _later(window.startAt, earliest);
    final end = _earlier(window.endAt, input.horizonEnd);
    if (start.isBefore(end)) {
      clipped.add(ScheduleWindow(startAt: start, endAt: end));
    }
  }

  final result = <ScheduleWindow>[];
  for (final window in clipped) {
    result.addAll(_splitByLocalDay(window));
  }
  final minimum = Duration(minutes: input.preferences.minimumBlockMinutes);
  final usable = result.where((window) => window.duration >= minimum).toList();
  usable.sort(_compareWindows);
  return usable;
}

/// 契约 `preferences.day_start_minute` / `day_end_minute` 才是前端直传的形状，
/// 显式给出 [ScheduleInput.availability] 时以它为准，否则由偏好逐日推导。
List<ScheduleWindow> _effectiveAvailability(ScheduleInput input) {
  if (input.availability.isNotEmpty) return input.availability.toList();

  final preferences = input.preferences;
  final windows = <ScheduleWindow>[];
  final last = scheduleDayOnly(input.horizonEnd);
  var cursor = scheduleDayOnly(input.horizonStart);
  while (!cursor.isAfter(last)) {
    windows.add(
      ScheduleWindow(
        startAt: cursor.add(Duration(minutes: preferences.dayStartMinute)),
        endAt: cursor.add(Duration(minutes: preferences.dayEndMinute)),
      ),
    );
    cursor = cursor.add(const Duration(days: 1));
  }
  return windows;
}

Iterable<ScheduleWindow> _splitByLocalDay(ScheduleWindow window) sync* {
  var cursor = window.startAt;
  while (cursor.isBefore(window.endAt)) {
    final dayEnd = scheduleDayOnly(cursor).add(const Duration(days: 1));
    final end = _earlier(dayEnd, window.endAt);
    if (cursor.isBefore(end)) {
      yield ScheduleWindow(startAt: cursor, endAt: end);
    }
    cursor = dayEnd;
  }
}

/// 可用窗口减去硬约束占用，得到真正的空闲片段。
List<ScheduleWindow> _freeWindows(
  List<ScheduleWindow> usable,
  ScheduleInput input,
) {
  final busy = input.fixedBlocks.map((block) => block.window).toList()
    ..sort(_compareWindows);

  final result = <ScheduleWindow>[];
  for (final window in usable) {
    var cursor = window.startAt;
    for (final block in busy) {
      if (_atOrBefore(block.endAt, cursor)) continue;
      if (_atOrAfter(block.startAt, window.endAt)) break;
      final gapEnd = _earlier(block.startAt, window.endAt);
      if (cursor.isBefore(gapEnd)) {
        result.add(ScheduleWindow(startAt: cursor, endAt: gapEnd));
      }
      cursor = _later(cursor, _earlier(block.endAt, window.endAt));
      if (!cursor.isBefore(window.endAt)) break;
    }
    if (cursor.isBefore(window.endAt)) {
      result.add(ScheduleWindow(startAt: cursor, endAt: window.endAt));
    }
  }

  final collapsed = <ScheduleWindow>[];
  for (final window in result) {
    if (window.isEmpty) continue;
    final last = collapsed.isEmpty ? null : collapsed.last;
    // 合并只在同一自然日内进行：跨零点相邻的两段一旦合并，
    // 就会重新长出跨日窗口，任务块不得跨日本地日的保证会被破坏。
    final mergeable =
        last != null &&
        _atOrAfter(last.endAt, window.startAt) &&
        scheduleDayOnly(last.startAt).isAtSameMomentAs(
          scheduleDayOnly(window.startAt),
        );
    if (mergeable && last != null) {
      collapsed[collapsed.length - 1] = ScheduleWindow(
        startAt: last.startAt,
        endAt: _later(last.endAt, window.endAt),
      );
    } else {
      collapsed.add(window);
    }
  }
  collapsed.sort(_compareWindows);
  return collapsed;
}

/// 找出相互重叠的硬约束。只用于解释，不会被 reposition。
List<ScheduleFixedBlock> _overlappingFixedBlocks(ScheduleInput input) {
  final sorted = input.fixedBlocks.toList()
    ..sort((a, b) {
      final start = a.startAt.compareTo(b.startAt);
      return start != 0 ? start : a.ownerId.compareTo(b.ownerId);
    });

  final hits = <ScheduleFixedBlock>[];
  final seen = <String>{};
  for (var i = 1; i < sorted.length; i++) {
    final current = sorted[i];
    for (var j = 0; j < i; j++) {
      final other = sorted[j];
      if (current.startAt.isBefore(other.endAt)) {
        if (seen.add(other.ownerId)) hits.add(other);
        if (seen.add(current.ownerId)) hits.add(current);
      }
    }
  }
  return hits;
}

/// 排序：截止最紧的先排，其次优先级，最后用 taskId 兜底保证稳定。
List<ScheduleTaskDemand> _orderedDemands(ScheduleInput input) {
  final ordered = input.demands.toList();
  ordered.sort((a, b) {
    final deadline = _deadlineRank(a, input).compareTo(_deadlineRank(b, input));
    if (deadline != 0) return deadline;
    final priority = b.priority.compareTo(a.priority);
    if (priority != 0) return priority;
    return a.taskId.compareTo(b.taskId);
  });
  return ordered;
}

DateTime _deadlineRank(ScheduleTaskDemand demand, ScheduleInput input) {
  final deadline = demand.deadline;
  if (deadline == null) return input.horizonEnd;
  return deadline.latestEndAt;
}

/// 本地日文本标签，用于生成可读且不重复的 changeId。
String _dayTag(DateTime instant) {
  final day = scheduleDayOnly(instant);
  final month = day.month.toString().padLeft(2, '0');
  final date = day.day.toString().padLeft(2, '0');
  return '${day.year}-$month-$date';
}

/// 本次排程要用的时长。
///
/// 契约第 5.6 节的优先级：**任务目标 > 服务端快照估算 > 兜底**，兜底值为
/// `max(preferences.minimum_block_minutes, 30)` 分钟。
/// 周期任务的目标由 `remaining_minutes_today` 折算：
/// - 非空：当日剩余就是本次要排的量（已扣掉当天做完的部分）；
/// - 为 0：当天不再排程（任务已完成），返回 `minutes = 0`，
///   调用方据此既不生成 block、也不计入 `unplanned_tasks`
///   ——「未安排不等于完成」，而这里恰恰是完成；
/// - 为空：按完整 `duration_target_seconds` 排。
///
/// `fromTarget` 决定 `duration_source` 是 `task_target` 还是 `scheduler_estimate`；
/// 只有任务目标算 `task_target`，快照估算与兜底一律算 `scheduler_estimate`，
/// 不得伪装成任务固有属性。
({int minutes, bool fromTarget}) _durationOf(
  ScheduleTaskDemand demand,
  ScheduleInput input,
) {
  final remainingToday = demand.remainingMinutesToday;
  if (demand.taskKind == ScheduleTaskKind.recurring && remainingToday != null) {
    // = 0 是「当天已做完」，不是「没有时长依据」：不能落到第三级兜底。
    if (remainingToday <= 0) return (minutes: 0, fromTarget: true);
    return (minutes: remainingToday, fromTarget: true);
  }

  final target = demand.targetDurationSeconds;
  if (target != null && target > 0) {
    return (
      minutes: (target / Duration.secondsPerMinute).ceil(),
      fromTarget: true,
    );
  }

  if (demand.requiredMinutes > 0) {
    return (minutes: demand.requiredMinutes, fromTarget: false);
  }

  // 兜底：既没有任务目标，也没有快照估算。
  final minimum = input.preferences.minimumBlockMinutes;
  return (minutes: minimum > 30 ? minimum : 30, fromTarget: false);
}

/// 在空闲片段中为一条需求找位置：最早可行优先，不拆分。
ProposedBlock? _placeDemand(
  List<ScheduleWindow> free,
  ScheduleTaskDemand demand,
  ScheduleInput input,
) {
  final duration = _durationOf(demand, input);
  if (duration.minutes <= 0) return null;
  final need = Duration(minutes: duration.minutes);
  for (final window in free) {
    var start = _later(window.startAt, input.now);
    final earliest = demand.earliestStartAt;
    if (earliest != null) start = _later(start, earliest);

    var latestEnd = window.endAt;
    final deadline = demand.deadline;
    if (deadline != null) latestEnd = _earlier(latestEnd, deadline.latestEndAt);

    if (!start.isBefore(latestEnd)) continue;
    if (latestEnd.difference(start) < need) continue;

    return ProposedBlock(
      taskId: demand.taskId,
      title: demand.title,
      startAt: start,
      endAt: start.add(need),
      taskKind: demand.taskKind,
      hasDurationTarget: duration.fromTarget,
    );
  }
  return null;
}

/// 从空闲片段中扣除已占用的时段。
List<ScheduleWindow> _subtract(List<ScheduleWindow> free, ScheduleWindow taken) {
  final result = <ScheduleWindow>[];
  for (final window in free) {
    if (_atOrBefore(window.endAt, taken.startAt) ||
        _atOrAfter(window.startAt, taken.endAt)) {
      result.add(window);
      continue;
    }
    if (window.startAt.isBefore(taken.startAt)) {
      result.add(ScheduleWindow(startAt: window.startAt, endAt: taken.startAt));
    }
    if (taken.endAt.isBefore(window.endAt)) {
      result.add(ScheduleWindow(startAt: taken.endAt, endAt: window.endAt));
    }
  }
  result.sort(_compareWindows);
  return result;
}

UnplannedTask _unplanned(
  ScheduleTaskDemand demand,
  int remainingMinutes,
  UnplannedReason reason,
  String reasonText,
) {
  return UnplannedTask(
    taskId: demand.taskId,
    title: demand.title,
    remainingMinutes: remainingMinutes,
    reason: reason,
    reasonText: reasonText,
  );
}

String _clock(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// 生成一版完整排程提案。
///
/// 输出永远只是建议。即便输入里存在硬约束重叠，
/// 也不会通过移动课程或会议来「解决」它，只会记录并在旁边避让。
ScheduleProposal generateSchedule(ScheduleInput input) {
  final notes = <ScheduleNote>[];
  final overlapping = _overlappingFixedBlocks(input);
  for (final block in overlapping) {
    notes.add(
      ScheduleNote(
        code: 'FIXED_BLOCKS_OVERLAP',
        taskId: block.ownerId,
        message: '${block.title ?? '日程'} 与其它课程/会议时间重叠。'
            '排程不会移动它们，请到日历确认是否录入有误。',
      ),
    );
  }

  // 固定课程/会议一律保留，从不为了让位而被移动——这条要能被机器读出来。
  if (input.fixedBlocks.isNotEmpty) {
    notes.add(
      const ScheduleNote(
        code: 'PRESERVED_FIXED_EVENTS',
        message: '保留了固定课程和临时会议。',
      ),
    );
  }

  final usable = _usableWindows(input);
  final ordered = _orderedDemands(input);

  if (usable.isEmpty) {
    notes.add(
      const ScheduleNote(
        code: 'NO_AVAILABILITY_WINDOW',
        message: '当前没有可用的时间窗口，无法生成排程建议。',
      ),
    );
    return ScheduleProposal(
      unplannedTasks: ordered
          .map(
            (demand) => _unplanned(
              demand,
              _durationOf(demand, input).minutes,
              UnplannedReason.noAvailability,
              '没有开放任何时间窗口，请先设置可用时段。',
            ),
          )
          .toList(),
      notes: notes,
    );
  }

  var free = _freeWindows(usable, input);
  if (free.isEmpty) {
    notes.add(
      const ScheduleNote(
        code: 'AVAILABILITY_SATURATED',
        message: '可用时间已被课程或会议占满，无法插入新的安排。',
      ),
    );
    return ScheduleProposal(
      unplannedTasks: ordered
          .map(
            (demand) => _unplanned(
              demand,
              _durationOf(demand, input).minutes,
              UnplannedReason.overlapsFixed,
              '开放时段已被课程或会议占满。',
            ),
          )
          .toList(),
      notes: notes,
    );
  }

  final changes = <ProposedBlock>[];
  final unplanned = <UnplannedTask>[];

  for (final demand in ordered) {
    final duration = _durationOf(demand, input);

    // remaining_minutes_today == 0 表示当天已经做完：既不排，也不记为未安排。
    if (duration.minutes == 0 &&
        demand.taskKind == ScheduleTaskKind.recurring &&
        demand.remainingMinutesToday != null) {
      notes.add(
        ScheduleNote(
          code: 'ALREADY_DONE_TODAY',
          taskId: demand.taskId,
          message: '${demand.title} 当天目标已完成，不再重复排程。',
        ),
      );
      continue;
    }

    // 补上第三级兜底后，正常输入到不了这里（时长至少 30 分钟）。
    // `NO_VALID_DURATION` 已被 M0 移出 v1 公共枚举，因此这里连内部码都不记，
    // 直接跳过——不产生任何需要服务端再过滤一次的输出。
    if (duration.minutes <= 0) continue;

    final deadline = demand.deadline;
    if (deadline != null && deadline.isPast(input.now)) {
      unplanned.add(
        _unplanned(
          demand,
          duration.minutes,
          UnplannedReason.pastDeadline,
          '截止时间已过，需要先调整时间再排。',
        ),
      );
      continue;
    }

    final block = _placeDemand(free, demand, input);
    if (block == null) {
      unplanned.add(
        _unplanned(
          demand,
          duration.minutes,
          UnplannedReason.windowInsufficient,
          '剩余可用时间不足 ${duration.minutes} 分钟。',
        ),
      );
      continue;
    }

    changes.add(block);
    free = _subtract(free, block.window);
    notes.add(
      ScheduleNote(
        code: 'SCHEDULED',
        taskId: demand.taskId,
        message: '${demand.title} 安排在 ${_clock(block.startAt)}–'
            '${_clock(block.endAt)}。',
      ),
    );

    // 估算必须被显式声明为估算：它不写回 Task，也不得被当成任务固有属性。
    if (block.durationSource == 'scheduler_estimate') {
      notes.add(
        ScheduleNote(
          code: 'ESTIMATED_DURATION',
          taskId: demand.taskId,
          message: '${demand.title} 的 ${duration.minutes} 分钟为调度估算；'
              '只持久化计划开始时间。',
        ),
      );
    }
  }

  changes.sort((a, b) {
    final start = a.startAt.compareTo(b.startAt);
    return start != 0 ? start : a.taskId.compareTo(b.taskId);
  });

  return ScheduleProposal(
    blocks: changes,
    changes: _buildChanges(changes),
    unplannedTasks: unplanned,
    notes: notes,
  );
}

bool _isInsideAny(List<ScheduleWindow> usable, ScheduleWindow candidate) {
  for (final window in usable) {
    if (_atOrBefore(window.startAt, candidate.startAt) &&
        _atOrBefore(candidate.endAt, window.endAt)) {
      return true;
    }
  }
  return false;
}

/// 硬约束变化后的最小扰动重排。
///
/// 策略：上一版里没被新课程/会议撞到的块原样保留；
/// 只有真正冲突的柔性任务才重新找位置，其余尽量不动。
ScheduleProposal repairSchedule(
  ScheduleInput input,
  ScheduleProposal previous,
) {
  final notes = <ScheduleNote>[];
  for (final block in _overlappingFixedBlocks(input)) {
    notes.add(
      ScheduleNote(
        code: 'FIXED_BLOCKS_OVERLAP',
        taskId: block.ownerId,
        message: '${block.title ?? '日程'} 与其它课程/会议时间重叠。'
            '重排不会移动它们，请到日历确认是否录入有误。',
      ),
    );
  }

  final usable = _usableWindows(input);
  final demandById = <String, ScheduleTaskDemand>{
    for (final demand in input.demands) demand.taskId: demand,
  };

  final kept = <ProposedBlock>[];
  final displaced = <ScheduleTaskDemand>[];
  final handled = <String>{};

  for (final block in previous.blocks) {
    final demand = demandById[block.taskId];
    final window = block.window;
    final deadline = demand?.deadline;
    final deadlineBroken =
        deadline != null && block.endAt.isAfter(deadline.latestEndAt);

    final isValid =
        _isInsideAny(usable, window) &&
        !input.fixedBlocks
            .map((fixed) => fixed.window)
            .any(window.overlaps) &&
        !deadlineBroken;

    if (isValid) {
      kept.add(
        ProposedBlock(
          taskId: block.taskId,
          title: block.title,
          startAt: block.startAt,
          endAt: block.endAt,
          taskKind: block.taskKind,
          hasDurationTarget: block.hasDurationTarget,
          movedFromPreviousPlan: false,
        ),
      );
      handled.add(block.taskId);
      continue;
    }

    displaced.add(
      demand ??
          ScheduleTaskDemand(
            taskId: block.taskId,
            title: block.title,
            requiredMinutes: block.minutes,
            taskKind: block.taskKind,
          ),
    );
    handled.add(block.taskId);
  }

  // 上一版没排进去的、以及新加入的任务，都再给一次机会。
  for (final demand in input.demands) {
    if (handled.contains(demand.taskId)) continue;
    displaced.add(demand);
  }

  final busy = <ScheduleWindow>[
    ...input.fixedBlocks.map((block) => block.window),
    ...kept.map((block) => block.window),
  ];
  var free = _subtractAll(usable, busy);

  final moved = <ProposedBlock>[];
  final unplanned = <UnplannedTask>[];

  final ordered = displaced.toList();
  ordered.sort((a, b) {
    final deadline = _deadlineRank(a, input).compareTo(_deadlineRank(b, input));
    if (deadline != 0) return deadline;
    final priority = b.priority.compareTo(a.priority);
    if (priority != 0) return priority;
    return a.taskId.compareTo(b.taskId);
  });

  for (final demand in ordered) {
    final durationMinutes = _durationOf(demand, input).minutes;
    if (durationMinutes <= 0) continue;
    final deadline = demand.deadline;
    if (deadline != null && deadline.isPast(input.now)) {
      unplanned.add(
        _unplanned(
          demand,
          durationMinutes,
          UnplannedReason.pastDeadline,
          '截止时间已过，需要先调整时间再排。',
        ),
      );
      continue;
    }

    final block = _placeDemand(free, demand, input);
    if (block == null) {
      unplanned.add(
        _unplanned(
          demand,
          durationMinutes,
          UnplannedReason.windowInsufficient,
          '剩余可用时间不足 $durationMinutes 分钟。',
        ),
      );
      continue;
    }

    moved.add(
      ProposedBlock(
        taskId: block.taskId,
        title: block.title,
        startAt: block.startAt,
        endAt: block.endAt,
        taskKind: block.taskKind,
        hasDurationTarget: block.hasDurationTarget,
        movedFromPreviousPlan: true,
      ),
    );
    notes.add(
      ScheduleNote(
        code: 'DISPLACED_BY_FIXED',
        taskId: demand.taskId,
        message: '${demand.title} 与新增日程冲突，'
            '移到 ${_clock(block.startAt)}–${_clock(block.endAt)}。',
      ),
    );
    free = _subtract(free, block.window);
  }

  final changes = <ProposedBlock>[...kept, ...moved];
  changes.sort((a, b) {
    final start = a.startAt.compareTo(b.startAt);
    return start != 0 ? start : a.taskId.compareTo(b.taskId);
  });

  final movedCount = moved.length;
  notes.add(
    ScheduleNote(
      code: 'REPAIR_SUMMARY',
      message: movedCount == 0
          ? '新增日程与现有安排无冲突，计划保持原样。'
          : '共移动 $movedCount 处安排，其余保持不变。',
    ),
  );

  return ScheduleProposal(
    blocks: changes,
    changes: _buildChanges(changes),
    unplannedTasks: unplanned,
    notes: notes,
  );
}

List<ScheduleWindow> _subtractAll(
  List<ScheduleWindow> usable,
  List<ScheduleWindow> busy,
) {
  var free = usable.toList()..sort(_compareWindows);
  for (final block in [...busy]..sort(_compareWindows)) {
    var next = <ScheduleWindow>[];
    for (final window in free) {
      if (_atOrBefore(window.endAt, block.startAt) ||
          _atOrAfter(window.startAt, block.endAt)) {
        next.add(window);
        continue;
      }
      if (window.startAt.isBefore(block.startAt)) {
        next.add(ScheduleWindow(startAt: window.startAt, endAt: block.startAt));
      }
      if (block.endAt.isBefore(window.endAt)) {
        next.add(ScheduleWindow(startAt: block.endAt, endAt: window.endAt));
      }
    }
    next.sort(_compareWindows);
    free = next;
  }
  return free;
}


/// 把展示区块翻译成契约白名单里的两种可持久化变更。
///
/// 周期任务只能走 `upsert_daily_override`（写单日例外），
/// 单次事项只能走 `schedule_one_time`。两者都不碰课程规则，也不改长期周期规则。
List<ProposedScheduleChange> _buildChanges(List<ProposedBlock> blocks) {
  final changes = <ProposedScheduleChange>[];
  for (final block in blocks) {
    // 同一任务在不同日期各有一条变更时，changeId 必须区分，
    // 否则服务端无法定位被拒的那一条。
    final changeId = 'chg-${block.taskId}-${_dayTag(block.startAt)}';
    if (block.taskKind == ScheduleTaskKind.oneTime) {
      changes.add(
        ScheduleOneTimeChange(
          changeId: changeId,
          taskId: block.taskId,
          plannedDate: scheduleDayOnly(block.startAt),
          scheduledAt: block.startAt,
        ),
      );
      continue;
    }
    final startMinute = minuteOfDay(block.startAt);
    var endMinute = minuteOfDay(block.endAt);
    if (endMinute <= startMinute) endMinute = 1440;
    changes.add(
      UpsertDailyOverrideChange(
        changeId: changeId,
        itemKind: block.taskKind,
        itemId: block.taskId,
        localDate: scheduleDayOnly(block.startAt),
        plannedStartMinute: startMinute,
        plannedEndMinute: endMinute,
      ),
    );
  }
  return changes;
}
