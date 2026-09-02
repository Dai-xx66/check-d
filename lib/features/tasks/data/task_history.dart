import 'dart:convert';

import '../../../core/database/app_database.dart';
import '../domain/task_models.dart';

class TaskHistory {
  TaskHistory(
    LocalTask task,
    LongTermTaskRecord goal,
    TaskScheduleRecord schedule,
    List<TaskRevisionRecord> revisions,
  ) {
    final indexed = revisions.indexed.toList()
      ..sort((a, b) {
        final time = a.$2.changedAt.compareTo(b.$2.changedAt);
        return time == 0 ? a.$1.compareTo(b.$1) : time;
      });
    final ordered = indexed.map((entry) => entry.$2).toList();
    _initial = {
      'name': task.name,
      'color': task.colorValue,
      'icon_name': task.iconName,
      'tag_id': task.tagId,
      'starts_on': schedule.startsOn,
      'ends_on': schedule.endsOn,
      'schedule_type': schedule.scheduleType,
      'weekdays': WeekdayMask.toDays(schedule.weekdaysMask).toList(),
      'status': task.status,
      'check_mode': goal.checkMode,
      'target_duration_seconds': goal.targetDurationSeconds,
    };
    if (ordered.isNotEmpty) {
      _initial.addAll(
        jsonDecode(ordered.first.beforeJson ?? ordered.first.afterJson)
            as Map<String, dynamic>,
      );
      if (ordered.first.beforeJson == null) _initial['status'] = 'active';
    }
    firstDay = DateTime.parse(_initial['starts_on'] as String);
    for (final revision in ordered) {
      final data = jsonDecode(revision.afterJson) as Map<String, dynamic>;
      final changedDay = dateOnly(revision.changedAt.toLocal());
      final inactive =
          data['status'] == 'archived' || data['status'] == 'paused';
      final effectiveDay = inactive
          ? DateTime(changedDay.year, changedDay.month, changedDay.day + 1)
          : changedDay;
      _changes.add((effectiveDay, data));
      final starts = DateTime.tryParse(data['starts_on'] as String? ?? '');
      if (starts != null && starts.isBefore(firstDay)) firstDay = starts;
    }
  }

  late final Map<String, dynamic> _initial;
  final _changes = <(DateTime, Map<String, dynamic>)>[];
  late DateTime firstDay;

  Map<String, dynamic> on(DateTime date) {
    final day = dateOnly(date);
    final result = {..._initial};
    for (final change in _changes) {
      if (!change.$1.isAfter(day)) result.addAll(change.$2);
    }
    return result;
  }
}
