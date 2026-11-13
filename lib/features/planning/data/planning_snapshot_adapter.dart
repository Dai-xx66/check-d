import '../../../features/calendar/domain/calendar_occurrence_builder.dart';
import '../../../features/courses/domain/course_models.dart';
import '../../../features/schedule/domain/day_schedule_models.dart';
import '../../../features/tasks/domain/task_models.dart';

/// Builds a read-only, versioned DTO from CheckD domain models.
/// Course occurrences must be produced by CheckD's canonical occurrence builder.
/// This adapter does not imply that the supplied data is server-current.
class PlanningSnapshotAdapter {
  const PlanningSnapshotAdapter();

  Map<String, Object?> build({
    required String subjectRef,
    required String source,
    required DateTime capturedAt,
    required String version,
    required String syncState,
    required DateTime now,
    required DateTime horizonEnd,
    required DateTime date,
    required List<TaskDetails> tasks,
    required List<CourseDetails> courses,
    required List<DailyItemOverride> overrides,
    List<ScheduleTemplateDetails> templates = const [],
    List<SemesterDetails> semesters = const [],
    Map<String, int?> remainingSecondsByTask = const {},
    int minimumBlockMinutes = 30,
  }) {
    if (subjectRef.isEmpty || version.isEmpty) {
      throw ArgumentError('subjectRef and version are required');
    }
    if (!{'current', 'pending_local_changes', 'unknown'}.contains(syncState)) {
      throw ArgumentError.value(syncState, 'syncState');
    }
    final occurrences = buildCourseOccurrencesForDate(
      date: date,
      courses: courses,
      overrides: overrides,
      templates: templates,
      semesters: semesters,
    );
    final busy = <Map<String, Object?>>[];
    for (final occurrence in occurrences) {
      final start = occurrence.startMinute;
      final end = occurrence.endMinute;
      if (start == null || end == null || end <= start) continue;
      final day = DateTime(date.year, date.month, date.day);
      busy.add({
        'source_id': occurrence.id,
        'kind': 'course',
        'starts_at': _localMinute(day, start).toUtc().toIso8601String(),
        'ends_at': _localMinute(day, end).toUtc().toIso8601String(),
      });
    }
    final taskDtos = <Map<String, Object?>>[];
    for (final task in tasks) {
      if (task.kind != TaskKind.oneTime ||
          task.isCompleted ||
          task.status != TaskLifecycle.active) {
        continue;
      }
      final deadline = task.deadline;
      taskDtos.add({
        'task_id': task.id,
        'name': task.name,
        'kind': 'one_time',
        'status': task.status.name,
        'completion_status': task.isCompleted ? 'completed' : 'pending',
        'remaining_seconds': remainingSecondsByTask[task.id],
        'remaining_effort_state':
            remainingSecondsByTask.containsKey(task.id) &&
                remainingSecondsByTask[task.id] != null
            ? 'known'
            : 'unknown',
        'effort_source': remainingSecondsByTask[task.id] == null
            ? null
            : 'provided_snapshot',
        'planned_at': task.scheduledAt?.toUtc().toIso8601String(),
        'planned_date': task.plannedDate == null
            ? null
            : _dateOnly(task.plannedDate!),
        'available_from': task.availableFrom == null
            ? null
            : _dateOnly(task.availableFrom!),
        'deadline_date': deadline?.date == null
            ? null
            : _dateOnly(deadline!.date!),
        'deadline_at': deadline?.at?.toUtc().toIso8601String(),
        'updated_at': task.updatedAt.toUtc().toIso8601String(),
      });
    }
    final provisional = syncState != 'current';
    return {
      'schema_version': 'checkd.planning.snapshot.v1',
      'subject_ref': subjectRef,
      'source': source,
      'captured_at': capturedAt.toUtc().toIso8601String(),
      'version': version,
      'sync_state': syncState,
      'provisional': provisional,
      'execution_eligible': false,
      'timezone': 'Asia/Shanghai',
      'now': now.toUtc().toIso8601String(),
      'horizon_end': horizonEnd.toUtc().toIso8601String(),
      'tasks': taskDtos,
      'course_occurrences': busy,
      'occupied_blocks': const <Map<String, Object?>>[],
      'unknown_effort_task_ids': taskDtos
          .where((t) => t['remaining_seconds'] == null)
          .map((t) => t['task_id'])
          .toList(),
    };
  }

  static DateTime _localMinute(DateTime day, int minute) =>
      DateTime(day.year, day.month, day.day).add(Duration(minutes: minute));

  static String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
