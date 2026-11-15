import '../../../features/calendar/domain/calendar_models.dart';
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
    List<CalendarOccurrence>? resolvedCourseOccurrences,
    Map<String, int?> remainingSecondsByTask = const {},
    List<Map<String, Object?>> occupiedBlocks = const [],
    List<Map<String, Object?>> timerFacts = const [],
    List<Map<String, Object?>> recurringOccurrences = const [],
    List<String> unmodeledRecurringOccurrenceIds = const [],
    int minimumBlockMinutes = 30,
    Duration previewSafetyLead = Duration.zero,
  }) {
    if (subjectRef.isEmpty || version.isEmpty) {
      throw ArgumentError('subjectRef and version are required');
    }
    if (!{'current', 'pending_local_changes', 'unknown'}.contains(syncState)) {
      throw ArgumentError.value(syncState, 'syncState');
    }
    final occurrences =
        resolvedCourseOccurrences ??
        buildCourseOccurrencesForDate(
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
      final day = DateTime(
        occurrence.date.year,
        occurrence.date.month,
        occurrence.date.day,
      );
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
        // The committed TaskDetails model has only the existing one-time
        // scheduledAt value. It does not expose date-only deadline or
        // available-from metadata, so preserve those as unknown/null.
        'earliest_start': now.add(previewSafetyLead).toUtc().toIso8601String(),
        'effort_source': remainingSecondsByTask[task.id] == null
            ? null
            : 'provided_snapshot',
        'planned_at': task.scheduledAt?.toUtc().toIso8601String(),
        'planned_date': null,
        'available_from': null,
        'deadline_date': null,
        'deadline_at': null,
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
      'occupied_blocks': occupiedBlocks,
      'timer_facts': timerFacts,
      'recurring_occurrences': recurringOccurrences,
      'unmodeled_recurring_occurrence_ids': unmodeledRecurringOccurrenceIds,
      'unknown_effort_task_ids': taskDtos
          .where((t) => t['remaining_seconds'] == null)
          .map((t) => t['task_id'])
          .toList(),
    };
  }

  static DateTime _localMinute(DateTime day, int minute) => DateTime.utc(
    day.year,
    day.month,
    day.day,
    0,
    minute,
  ).subtract(const Duration(hours: 8));
}
