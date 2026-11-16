import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/calendar/domain/calendar_occurrence_builder.dart';
import 'package:check_d/features/courses/data/course_repository.dart';
import 'package:check_d/features/courses/data/semester_repository.dart';
import 'package:check_d/features/schedule/data/day_schedule_repository.dart';
import 'package:check_d/features/calendar/domain/calendar_models.dart';

/// Normalized output of CheckD's canonical Flutter course occurrence builder.
/// Times remain local minute ranges so clients never invent UTC offsets for
/// Asia/Shanghai calendar rules.
class CourseOccurrenceSnapshot {
  const CourseOccurrenceSnapshot({
    required this.userId,
    required this.fromDate,
    required this.throughDate,
    required this.generatedAt,
    required this.timezone,
    required this.builderVersion,
    required this.courseDataVersion,
    required this.deviceId,
    required this.localGeneration,
    required this.occurrences,
  });

  final String userId;
  final String fromDate;
  final String throughDate;
  final DateTime generatedAt;
  final String timezone;
  final String builderVersion;
  final String courseDataVersion;
  final String deviceId;
  final int localGeneration;
  final List<Map<String, Object?>> occurrences;

  Map<String, Object?> toJson() => {
    'from_date': fromDate,
    'through_date': throughDate,
    'timezone': timezone,
    'generated_at': generatedAt.toUtc().toIso8601String(),
    'builder_version': builderVersion,
    'course_data_version': courseDataVersion,
    'device_id': deviceId,
    'local_generation': localGeneration,
    'occurrences': occurrences,
  };
}

/// Uses the real repositories and `buildCourseOccurrencesForDate`; this class
/// intentionally contains no recurrence, semester-week, or override logic.
class DriftCourseOccurrenceSnapshotRepository {
  DriftCourseOccurrenceSnapshotRepository({
    required String userId,
    required CourseRepository courses,
    required SemesterRepository semesters,
    required DayScheduleRepository schedule,
    required SyncQueueService syncQueue,
  }) : _userId = userId,
       _courses = courses,
       _semesters = semesters,
       _schedule = schedule,
       _syncQueue = syncQueue;

  static const timezone = 'Asia/Shanghai';
  static const builderVersion = 'checkd_flutter_course_occurrence_v1';
  static const maximumDays = 31;

  final String _userId;
  final CourseRepository _courses;
  final SemesterRepository _semesters;
  final DayScheduleRepository _schedule;
  final SyncQueueService _syncQueue;

  Future<CourseOccurrenceSnapshot> build({
    required DateTime from,
    required DateTime through,
  }) async {
    final start = _dateOnly(from);
    final end = _dateOnly(through);
    final dayCount = end.difference(start).inDays + 1;
    if (_userId.isEmpty || dayCount < 1 || dayCount > maximumDays) {
      throw ArgumentError('课程快照必须属于当前用户且覆盖 1–31 天。');
    }
    final checkpoint = await _syncQueue.settledCheckpoint(_userId);
    if (checkpoint == null) {
      throw StateError('本地同步队列未全部确认，不能发布可信课程快照。');
    }

    final courses = await _courses.loadCourses();
    final templates = await _courses.watchScheduleTemplates().first;
    final semesters = await _semesters.watchSemesters().first;
    final rows = <Map<String, Object?>>[];
    for (var offset = 0; offset < dayCount; offset++) {
      final date = start.add(Duration(days: offset));
      final overrides = await _schedule.loadOverridesForDate(date);
      final occurrences = buildCourseOccurrencesForDate(
        date: date,
        courses: courses,
        overrides: overrides,
        templates: templates,
        semesters: semesters,
      );
      for (final occurrence in occurrences) {
        final normalized = normalizeCourseOccurrence(occurrence);
        if (normalized != null) rows.add(normalized);
      }
    }
    rows.sort((a, b) {
      final day = (a['local_date']! as String).compareTo(
        b['local_date']! as String,
      );
      if (day != 0) return day;
      final startMinute = (a['start_minute']! as int).compareTo(
        b['start_minute']! as int,
      );
      if (startMinute != 0) return startMinute;
      return (a['occurrence_id']! as String).compareTo(
        b['occurrence_id']! as String,
      );
    });
    final latestLocalGeneration = await _syncQueue.currentLocalGeneration(
      checkpoint,
    );
    if (latestLocalGeneration != checkpoint.localGeneration ||
        await _syncQueue.settledCheckpoint(_userId) == null) {
      throw StateError('生成课程快照期间本地数据发生变化，请重新同步。');
    }
    return CourseOccurrenceSnapshot(
      userId: _userId,
      fromDate: _dateKey(start),
      throughDate: _dateKey(end),
      generatedAt: DateTime.now().toUtc(),
      timezone: timezone,
      builderVersion: builderVersion,
      courseDataVersion:
          'sha256:${sha256.convert(utf8.encode(jsonEncode(rows)))}',
      deviceId: checkpoint.deviceId,
      localGeneration: checkpoint.localGeneration,
      occurrences: List.unmodifiable(rows),
    );
  }
}

Map<String, Object?>? normalizeCourseOccurrence(CalendarOccurrence occurrence) {
  final start = occurrence.startMinute;
  final end = occurrence.endMinute;
  final course = occurrence.course;
  if (occurrence.type != CalendarOccurrenceType.course ||
      course == null ||
      start == null ||
      end == null) {
    return null;
  }
  if (start < 0 || start >= 1440 || end <= start || end > 1440) {
    throw StateError('课程 occurrence 超出单日有效时间范围。');
  }
  return {
    'occurrence_id': occurrence.id,
    'course_id': course.id,
    if (occurrence.courseRule != null)
      'schedule_rule_id': occurrence.courseRule!.id,
    'local_date': _dateKey(occurrence.date),
    'start_minute': start,
    'end_minute': end,
    'timezone': DriftCourseOccurrenceSnapshotRepository.timezone,
  };
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String _dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
