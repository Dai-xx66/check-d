import 'dart:convert';

/// Deterministic, read-only Dart planner for on-device previews.
///
/// This consumes the existing `checkd.planning.snapshot.v1` DTO. It mirrors
/// the Python reference engine's slot-based EDF approach, but exact algorithmic
/// equivalence is not claimed. Results can never authorize writes.
class LocalPlanningEngine {
  const LocalPlanningEngine();

  static const _timezone = 'Asia/Shanghai';
  static const _slotMinutes = 15;

  Map<String, Object?> preview(
    Map<String, Object?> snapshot, {
    String? expectedVersion,
  }) {
    try {
      final input = _PlanningInput.parse(snapshot);
      if (expectedVersion != null && expectedVersion != input.version) {
        return _error('SNAPSHOT_STALE', {'current_version': input.version});
      }
      final schedule = _generate(input);
      final incomplete = input.missingData.values.any(
        (items) => items.isNotEmpty,
      );
      final outcome = incomplete
          ? 'unknown_due_to_missing_data'
          : schedule['feasible'] == true
          ? 'found_feasible'
          : 'no_solution_found';
      return {
        'ok': true,
        'subject_ref': input.subjectRef,
        'snapshot_version': input.version,
        'snapshot_digest': _digest(snapshot),
        'captured_at': input.capturedAt.toIso8601String(),
        'sync_state': input.syncState,
        'provisional': input.provisional,
        'execution_eligible': false,
        'operation': 'preview',
        'outcome': outcome,
        'schedule': schedule,
        'missing_data': input.missingData,
        'optimality_proven': false,
        'availability_note': '候选时段只避让已知课程和已有安排；个人可用时段偏好尚未接入。',
      };
    } on _PlanningInputException catch (error) {
      return _error('INVALID_INPUT', {'validation_error': error.code});
    } on Object catch (error) {
      return _error('INVALID_INPUT', {'validation_error': '$error'});
    }
  }

  Map<String, Object?> simulateDelay(
    Map<String, Object?> snapshot, {
    required String taskId,
    required DateTime until,
  }) {
    try {
      final input = _PlanningInput.parse(snapshot);
      final target = input.tasks.firstWhereOrNull((task) => task.id == taskId);
      if (target == null) {
        final exists = input.taskRows.any((row) => row['task_id'] == taskId);
        if (!exists) return _error('NOT_FOUND');
        return {
          'ok': true,
          'snapshot_version': input.version,
          'execution_eligible': false,
          'delay_analysis': {
            'task_id': taskId,
            'status': 'unknown_due_to_missing_data',
            'before_feasible': null,
            'after_feasible': null,
            'before_slack_seconds': null,
            'after_slack_seconds': null,
            'slack_change_seconds': null,
            'affected_task_ids': <String>[],
            'optimality_proven': false,
          },
        };
      }
      final before = _generate(input);
      final after = _generate(
        input,
        delayedTaskId: taskId,
        delayedUntil: until.toUtc(),
      );
      final beforeSlack = _slack(input, target);
      final afterSlack = _slack(input, target, earliestStart: until.toUtc());
      final affected = <String>{};
      for (final block in [..._blocks(before), ..._blocks(after)]) {
        if (block['task_id'] != taskId) {
          affected.add(block['task_id']! as String);
        }
      }
      final incomplete = input.missingData.values.any(
        (items) => items.isNotEmpty,
      );
      return {
        'ok': true,
        'snapshot_version': input.version,
        'execution_eligible': false,
        'delay_analysis': {
          'task_id': taskId,
          'delayed_until': until.toUtc().toIso8601String(),
          'status': incomplete ? 'unknown_due_to_missing_data' : 'computed',
          'before_feasible': incomplete ? null : before['feasible'],
          'after_feasible': incomplete ? null : after['feasible'],
          'before_slack_seconds': beforeSlack,
          'after_slack_seconds': afterSlack,
          'slack_change_seconds': afterSlack - beforeSlack,
          'affected_task_ids': affected.toList()..sort(),
          'before': before,
          'after': after,
          'optimality_proven': false,
        },
      };
    } on _PlanningInputException catch (error) {
      return _error('INVALID_INPUT', {'validation_error': error.code});
    } on Object catch (error) {
      return _error('INVALID_INPUT', {'validation_error': '$error'});
    }
  }

  Map<String, Object?> assessRisks(Map<String, Object?> snapshot) {
    try {
      final input = _PlanningInput.parse(snapshot);
      final risks = <Map<String, Object?>>[];
      for (final row in input.taskRows) {
        final taskId = row['task_id']! as String;
        if (row['completion_status'] == 'completed') continue;
        final task = input.tasks.firstWhereOrNull((item) => item.id == taskId);
        final deadline = task?.deadline ?? _readDeadline(row);
        final plannedAt = row['planned_at'] == null
            ? null
            : _readInstant(row['planned_at']);
        final slack = task == null ? null : _slack(input, task);
        final reasons = <(String, String)>[];
        if (task != null && _slack(input, task) < 0) {
          reasons.add(('capacity_insufficient', 'high'));
        }
        if (plannedAt != null && plannedAt.isBefore(input.now)) {
          reasons.add(('plan_missed', 'medium'));
        }
        if (deadline != null && !deadline.isAfter(input.now)) {
          reasons.add(('deadline_passed', 'critical'));
        }
        if (slack != null && slack < 3600) {
          reasons.add(('buffer_below_threshold', 'medium'));
        }
        for (final (kind, severity) in reasons) {
          risks.add({
            'risk_key': '$taskId:$kind',
            'risk_type': kind,
            'severity': severity,
            'affected_task_ids': [taskId],
            'evidence': {'evaluated_at': input.now.toIso8601String()},
            'recommendation': '重新评估剩余时间与可行安排。',
            'evaluated_at': input.now.toIso8601String(),
          });
        }
      }
      final incomplete = input.missingData.values.any(
        (items) => items.isNotEmpty,
      );
      return {
        'ok': true,
        'snapshot_version': input.version,
        'execution_eligible': false,
        'risk_status': incomplete
            ? 'unknown_due_to_missing_data'
            : 'complete_for_snapshot',
        'risks': risks,
      };
    } on _PlanningInputException catch (error) {
      return _error('INVALID_INPUT', {'validation_error': error.code});
    } on Object catch (error) {
      return _error('INVALID_INPUT', {'validation_error': '$error'});
    }
  }

  Map<String, Object?> _generate(
    _PlanningInput input, {
    String? delayedTaskId,
    DateTime? delayedUntil,
  }) {
    final slots = _availableSlots(input);
    final placed = <Map<String, Object?>>[];
    final unplanned = <Map<String, Object?>>[];
    final taskById = {for (final task in input.tasks) task.id: task};
    final pending = taskById.keys.toSet();
    final completedAt = <String, DateTime>{};
    final failed = <String>{};
    for (final task in input.tasks) {
      if (task.dependsOn.any((id) => !taskById.containsKey(id))) {
        unplanned.add({'task_id': task.id, 'reason': 'unknown_dependency'});
        pending.remove(task.id);
        failed.add(task.id);
      }
    }
    while (pending.isNotEmpty) {
      final ready = pending
          .map((id) => taskById[id]!)
          .where(
            (task) => task.dependsOn.every(
              (id) => completedAt.containsKey(id) || failed.contains(id),
            ),
          )
          .toList();
      if (ready.isEmpty) {
        for (final id in pending.toList()..sort()) {
          unplanned.add({
            'task_id': id,
            'reason': 'dependency_cycle_or_missing_dependency',
          });
        }
        break;
      }
      ready.sort((left, right) {
        final priority = right.priority.compareTo(left.priority);
        if (priority != 0) return priority;
        final deadline = left.deadline.compareTo(right.deadline);
        return deadline != 0 ? deadline : left.id.compareTo(right.id);
      });
      final task = ready.first;
      pending.remove(task.id);
      if (task.dependsOn.any(failed.contains)) {
        unplanned.add({'task_id': task.id, 'reason': 'dependency_unplanned'});
        failed.add(task.id);
        continue;
      }
      if (task.remainingSeconds <= 0 || task.minimumBlockMinutes <= 0) {
        unplanned.add({
          'task_id': task.id,
          'reason': 'invalid_effort_or_minimum_block',
        });
        failed.add(task.id);
        continue;
      }
      var earliest = task.earliestStart;
      for (final dependency in task.dependsOn) {
        final finish = completedAt[dependency];
        if (finish != null && finish.isAfter(earliest)) earliest = finish;
      }
      if (task.id == delayedTaskId &&
          delayedUntil != null &&
          delayedUntil.isAfter(earliest)) {
        earliest = delayedUntil;
      }
      final eligible = slots
          .where(
            (slot) =>
                !slot.startsAt.isBefore(earliest) &&
                !slot.endsAt.isAfter(task.deadline),
          )
          .toList();
      final chosen = _chooseSlots(task, eligible);
      if (chosen.isEmpty) {
        unplanned.add({
          'task_id': task.id,
          'reason': 'no_slot_found_within_constraints',
        });
        failed.add(task.id);
        continue;
      }
      var remaining = task.remainingSeconds;
      final groups = <List<_PlanningBlock>>[];
      for (final slot in chosen) {
        if (groups.isNotEmpty && groups.last.last.endsAt == slot.startsAt) {
          groups.last.add(slot);
        } else {
          groups.add([slot]);
        }
      }
      for (final group in groups) {
        final capacity = group.fold<int>(0, (sum, slot) => sum + slot.seconds);
        final duration = capacity < remaining ? capacity : remaining;
        final end = group.first.startsAt.add(Duration(seconds: duration));
        placed.add(_serializeBlock(task.id, group.first.startsAt, end));
        remaining -= duration;
        for (final slot in group) {
          slots.remove(slot);
        }
      }
      completedAt[task.id] = placed
          .where((block) => block['task_id'] == task.id)
          .map((block) => DateTime.parse(block['ends_at']! as String))
          .reduce((a, b) => a.isAfter(b) ? a : b);
    }
    placed.sort(
      (a, b) => DateTime.parse(
        a['starts_at']! as String,
      ).compareTo(DateTime.parse(b['starts_at']! as String)),
    );
    final feasible = unplanned.isEmpty;
    return {
      'status': feasible ? 'feasible' : 'partial',
      'feasible': feasible,
      'blocks': placed,
      'unplanned_tasks': unplanned,
      'hard_constraints_satisfied': true,
      'optimality_proven': false,
      'limitation':
          'Deterministic EDF heuristic; failure to find a plan is not a proof of infeasibility.',
    };
  }

  List<_PlanningBlock> _chooseSlots(
    _PlanningTask task,
    List<_PlanningBlock> eligible,
  ) {
    final slotSeconds = _slotMinutes * 60;
    final needed = (task.remainingSeconds + slotSeconds - 1) ~/ slotSeconds;
    final minSlots =
        (task.minimumBlockMinutes + _slotMinutes - 1) ~/ _slotMinutes;
    final maxSlots = task.maximumContinuousMinutes == null
        ? null
        : (task.maximumContinuousMinutes! + _slotMinutes - 1) ~/ _slotMinutes;
    final chosen = <_PlanningBlock>[];
    if (!task.splittable) {
      var run = <_PlanningBlock>[];
      for (final slot in eligible) {
        if (run.isNotEmpty && run.last.endsAt != slot.startsAt) run = [];
        run.add(slot);
        if (run.length >= needed && (maxSlots == null || needed <= maxSlots)) {
          chosen.addAll(run.take(needed));
          break;
        }
      }
      return chosen;
    }
    var left = needed;
    var index = 0;
    while (index < eligible.length && left > 0) {
      final run = <_PlanningBlock>[eligible[index++]];
      while (index < eligible.length &&
          eligible[index].startsAt == run.last.endsAt) {
        run.add(eligible[index++]);
      }
      var offset = 0;
      while (offset < run.length && left > 0) {
        final capacity = (run.length - offset).clamp(0, maxSlots ?? run.length);
        final take = left < capacity ? left : capacity;
        if (take < (minSlots < left ? minSlots : left)) break;
        chosen.addAll(run.skip(offset).take(take));
        left -= take;
        offset += take;
        if (left > 0 && maxSlots != null && take == maxSlots) {
          final rest =
              (task.minimumRestMinutes + _slotMinutes - 1) ~/ _slotMinutes;
          if (rest == 0) break;
          offset += rest;
        }
      }
    }
    return left == 0 ? chosen : const [];
  }

  List<_PlanningBlock> _availableSlots(_PlanningInput input) {
    final busy = [...input.courseBlocks, ...input.occupiedBlocks]
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final merged = <_PlanningBlock>[];
    for (final block in busy) {
      if (!block.endsAt.isAfter(block.startsAt)) {
        throw const _PlanningInputException('invalid_busy_interval');
      }
      if (merged.isNotEmpty && !block.startsAt.isAfter(merged.last.endsAt)) {
        final previous = merged.removeLast();
        merged.add(
          _PlanningBlock(
            startsAt: previous.startsAt,
            endsAt: block.endsAt.isAfter(previous.endsAt)
                ? block.endsAt
                : previous.endsAt,
            kind: 'merged_busy',
          ),
        );
      } else {
        merged.add(block);
      }
    }
    final slots = <_PlanningBlock>[];
    var cursor = input.now;
    while (!cursor
        .add(const Duration(minutes: _slotMinutes))
        .isAfter(input.horizonEnd)) {
      final end = cursor.add(const Duration(minutes: _slotMinutes));
      final overlaps = merged.any(
        (block) =>
            cursor.isBefore(block.endsAt) && block.startsAt.isBefore(end),
      );
      if (!overlaps) slots.add(_PlanningBlock(startsAt: cursor, endsAt: end));
      cursor = end;
    }
    return slots;
  }

  int _slack(
    _PlanningInput input,
    _PlanningTask task, {
    DateTime? earliestStart,
  }) {
    final earliest =
        earliestStart != null && earliestStart.isAfter(task.earliestStart)
        ? earliestStart
        : task.earliestStart;
    final available = _availableSlots(input)
        .where(
          (slot) =>
              !slot.startsAt.isBefore(earliest) &&
              !slot.endsAt.isAfter(task.deadline),
        )
        .fold<int>(0, (sum, slot) => sum + slot.seconds);
    return available - task.remainingSeconds;
  }

  Map<String, Object?> _serializeBlock(
    String taskId,
    DateTime start,
    DateTime end,
  ) => {
    'task_id': taskId,
    'starts_at': start.toUtc().toIso8601String(),
    'ends_at': end.toUtc().toIso8601String(),
    'planned_seconds': end.difference(start).inSeconds,
    'status': 'proposed',
    'source': 'dart_edf_heuristic',
  };

  List<Map<String, Object?>> _blocks(Map<String, Object?> schedule) =>
      (schedule['blocks'] as List).cast<Map<String, Object?>>();

  String _digest(Map<String, Object?> snapshot) {
    var hash = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = (BigInt.one << 64) - BigInt.one;
    for (final byte in utf8.encode(jsonEncode(snapshot))) {
      hash = ((hash ^ BigInt.from(byte)) * prime) & mask;
    }
    return 'local-fnv64-${hash.toRadixString(16).padLeft(16, '0')}';
  }

  Map<String, Object?> _error(
    String code, [
    Map<String, Object?> details = const {},
  ]) => {
    'ok': false,
    if (code == 'INVALID_INPUT') 'outcome': 'invalid_input',
    'error': {
      'code': code,
      'message': code == 'SNAPSHOT_STALE'
          ? '数据版本已变化，请重新读取后生成预览。'
          : code == 'NOT_FOUND'
          ? '未找到可访问的规划数据。'
          : '规划请求无效。',
      'retryable': false,
      'details': details,
    },
  };
}

class _PlanningInput {
  const _PlanningInput({
    required this.subjectRef,
    required this.source,
    required this.capturedAt,
    required this.version,
    required this.syncState,
    required this.provisional,
    required this.now,
    required this.horizonEnd,
    required this.tasks,
    required this.taskRows,
    required this.courseBlocks,
    required this.occupiedBlocks,
    required this.missingData,
  });

  final String subjectRef;
  final String source;
  final DateTime capturedAt;
  final String version;
  final String syncState;
  final bool provisional;
  final DateTime now;
  final DateTime horizonEnd;
  final List<_PlanningTask> tasks;
  final List<Map<String, Object?>> taskRows;
  final List<_PlanningBlock> courseBlocks;
  final List<_PlanningBlock> occupiedBlocks;
  final Map<String, List<String>> missingData;

  factory _PlanningInput.parse(Map<String, Object?> data) {
    if (data.containsKey('user_id')) {
      throw const _PlanningInputException('caller_user_id_forbidden');
    }
    if (data['timezone'] != LocalPlanningEngine._timezone) {
      throw const _PlanningInputException('unsupported_timezone');
    }
    final subject = data['subject_ref'];
    final version = data['version'];
    final source = data['source'];
    final sync = data['sync_state'];
    if (subject is! String ||
        subject.isEmpty ||
        version is! String ||
        version.isEmpty ||
        source is! String ||
        sync is! String ||
        !{'current', 'pending_local_changes', 'unknown'}.contains(sync)) {
      throw const _PlanningInputException('snapshot_metadata_invalid');
    }
    final capturedAt = _readInstant(data['captured_at']);
    final now = _readInstant(data['now']);
    final horizonEnd = _readInstant(data['horizon_end']);
    if (horizonEnd.isBefore(now)) {
      throw const _PlanningInputException('horizon_before_now');
    }
    final rawTasks = data['tasks'];
    final rawCourses = data['course_occurrences'];
    final rawOccupied = data['occupied_blocks'];
    if (rawTasks is! List || rawCourses is! List || rawOccupied is! List) {
      throw const _PlanningInputException('snapshot_collections_invalid');
    }
    final tasks = <_PlanningTask>[];
    final rows = <Map<String, Object?>>[];
    final unknown = <String>[];
    final noDeadline = <String>[];
    final plannedUnknown = <String>[];
    final ids = <String>{};
    final occupied = <_PlanningBlock>[];
    for (final item in rawTasks) {
      if (item is! Map) throw const _PlanningInputException('task_not_object');
      final row = item.cast<String, Object?>();
      final id = row['task_id'];
      if (id is! String || id.isEmpty || !ids.add(id)) {
        throw const _PlanningInputException('task_id_invalid_or_duplicate');
      }
      rows.add(row);
      final planned = row['planned_at'] == null
          ? null
          : _readInstant(row['planned_at']);
      final effort = row['remaining_seconds'];
      final deadline = _readDeadline(row);
      if (effort == null) {
        unknown.add(id);
        if (planned != null) plannedUnknown.add(id);
        if (deadline == null && planned == null) noDeadline.add(id);
        continue;
      }
      if (effort is! int || effort <= 0) {
        throw const _PlanningInputException('remaining_seconds_invalid');
      }
      if (planned != null) {
        occupied.add(
          _PlanningBlock(
            startsAt: planned,
            endsAt: planned.add(Duration(seconds: effort)),
            taskId: id,
            kind: 'existing_task_plan',
          ),
        );
        continue;
      }
      if (deadline == null) {
        noDeadline.add(id);
        continue;
      }
      final minimum = row['minimum_block_minutes'] ?? 30;
      final priority = row['priority'] ?? 0;
      final maximum = row['maximum_continuous_minutes'];
      final rest = row['minimum_rest_minutes'] ?? 0;
      final dependencies = row['depends_on'] ?? const <Object?>[];
      if (minimum is! int ||
          priority is! int ||
          rest is! int ||
          (maximum != null && maximum is! int) ||
          dependencies is! List ||
          minimum <= 0 ||
          priority < 0 ||
          priority > 10 ||
          rest < 0) {
        throw const _PlanningInputException('task_constraints_invalid');
      }
      tasks.add(
        _PlanningTask(
          id: id,
          remainingSeconds: effort,
          deadline: deadline,
          earliestStart: row['earliest_start'] == null
              ? now
              : _readInstant(row['earliest_start']),
          splittable: row['splittable'] != false,
          minimumBlockMinutes: minimum,
          priority: priority,
          maximumContinuousMinutes: maximum as int?,
          minimumRestMinutes: rest,
          dependsOn: dependencies.whereType<String>().toList(),
        ),
      );
    }
    final courseBlocks = _readBlocks(rawCourses, 'course');
    occupied.addAll(_readBlocks(rawOccupied, 'existing_override'));
    final recurring =
        data['unmodeled_recurring_occurrence_ids'] ?? const <Object?>[];
    if (recurring is! List) {
      throw const _PlanningInputException('recurring_ids_invalid');
    }
    final missing = <String, List<String>>{
      'unknown_effort_task_ids': unknown,
      'missing_deadline_task_ids': noDeadline,
      'existing_plan_needing_effort_task_ids': plannedUnknown,
      'unmodeled_recurring_occurrence_ids': recurring
          .whereType<String>()
          .toList(),
    };
    return _PlanningInput(
      subjectRef: subject,
      source: source,
      capturedAt: capturedAt,
      version: version,
      syncState: sync,
      provisional: data['provisional'] == true || sync != 'current',
      now: now,
      horizonEnd: horizonEnd,
      tasks: tasks,
      taskRows: rows,
      courseBlocks: courseBlocks,
      occupiedBlocks: occupied,
      missingData: missing,
    );
  }
}

class _PlanningTask {
  const _PlanningTask({
    required this.id,
    required this.remainingSeconds,
    required this.deadline,
    required this.earliestStart,
    required this.splittable,
    required this.minimumBlockMinutes,
    required this.priority,
    required this.maximumContinuousMinutes,
    required this.minimumRestMinutes,
    required this.dependsOn,
  });

  final String id;
  final int remainingSeconds;
  final DateTime deadline;
  final DateTime earliestStart;
  final bool splittable;
  final int minimumBlockMinutes;
  final int priority;
  final int? maximumContinuousMinutes;
  final int minimumRestMinutes;
  final List<String> dependsOn;
}

class _PlanningBlock {
  const _PlanningBlock({
    required this.startsAt,
    required this.endsAt,
    this.taskId,
    this.kind = 'busy',
  });
  final DateTime startsAt;
  final DateTime endsAt;
  final String? taskId;
  final String kind;
  int get seconds => endsAt.difference(startsAt).inSeconds;
}

class _PlanningInputException implements Exception {
  const _PlanningInputException(this.code);
  final String code;
}

DateTime _readInstant(Object? value) {
  if (value is! String || !RegExp(r'(?:Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
    throw const _PlanningInputException('timezone_offset_required');
  }
  return DateTime.parse(value).toUtc();
}

DateTime? _readDeadline(Map<String, Object?> row) {
  if (row['deadline_at'] != null) return _readInstant(row['deadline_at']);
  final date = row['deadline_date'];
  if (date == null) return null;
  if (date is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
    throw const _PlanningInputException('date_only_format_invalid');
  }
  final parts = date.split('-').map(int.parse).toList();
  final normalized = DateTime.utc(parts[0], parts[1], parts[2]);
  if (normalized.year != parts[0] ||
      normalized.month != parts[1] ||
      normalized.day != parts[2]) {
    throw const _PlanningInputException('date_only_invalid');
  }
  return DateTime.utc(
    parts[0],
    parts[1],
    parts[2] + 1,
  ).subtract(const Duration(hours: 8));
}

List<_PlanningBlock> _readBlocks(Object? value, String fallbackKind) {
  if (value is! List) throw const _PlanningInputException('blocks_not_list');
  return [
    for (final item in value)
      if (item is Map)
        _PlanningBlock(
          startsAt: _readInstant(item['starts_at']),
          endsAt: _readInstant(item['ends_at']),
          taskId: item['task_id'] as String?,
          kind: item['kind'] as String? ?? fallbackKind,
        )
      else
        throw const _PlanningInputException('block_not_object'),
  ];
}

extension<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T element) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
