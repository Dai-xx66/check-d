import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_queue_service.dart';
import '../domain/course_models.dart';

class CourseRepository {
  CourseRepository({
    required AppDatabase database,
    required SyncQueueService syncQueue,
    required String userId,
  }) : _database = database,
       _syncQueue = syncQueue,
       _userId = userId;

  final AppDatabase _database;
  final SyncQueueService _syncQueue;
  final String _userId;
  final Uuid _uuid = const Uuid();

  Stream<List<CourseDetails>> watchCourses() {
    final query = _database.select(_database.courseRecords)
      ..where(
        (row) =>
            row.userId.equals(_userId) &
            row.deletedAt.isNull() &
            row.status.equals(CourseStatus.active.name),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.name)]);
    return query.watch().asyncMap((rows) => Future.wait(rows.map(_toDetails)));
  }

  Future<List<CourseDetails>> loadCourses() async {
    final rows =
        await (_database.select(_database.courseRecords)
              ..where(
                (row) =>
                    row.userId.equals(_userId) &
                    row.deletedAt.isNull() &
                    row.status.equals(CourseStatus.active.name),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.name)]))
            .get();
    return Future.wait(rows.map(_toDetails));
  }

  Stream<CourseDetails?> watchCourse(String courseId) {
    final query = _database.select(_database.courseRecords)
      ..where(
        (row) =>
            row.id.equals(courseId) &
            row.userId.equals(_userId) &
            row.deletedAt.isNull(),
      );
    return query.watchSingleOrNull().asyncMap(
      (row) => row == null ? null : _toDetails(row),
    );
  }

  Future<String> saveCourse(CourseDraft draft, {String? courseId}) async {
    if (draft.name.trim().isEmpty) {
      throw ArgumentError.value(draft.name, 'name', '请填写课程名称');
    }
    final now = DateTime.now().toUtc();
    final id = courseId ?? _uuid.v4();
    await _database
        .into(_database.courseRecords)
        .insertOnConflictUpdate(
          CourseRecordsCompanion.insert(
            id: id,
            userId: _userId,
            name: draft.name.trim(),
            colorValue: draft.colorValue,
            teacher: Value(_clean(draft.teacher)),
            classroom: Value(_clean(draft.classroom)),
            semester: Value(_clean(draft.semester)),
            notes: Value(_clean(draft.notes)),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _syncQueue.enqueue(
      entityType: 'courses',
      entityId: id,
      operation: SyncOperationType.upsert,
      payload: {
        'id': id,
        'name': draft.name.trim(),
        'color': draft.colorValue,
        'teacher': _clean(draft.teacher),
        'classroom': _clean(draft.classroom),
        'semester': _clean(draft.semester),
        'notes': _clean(draft.notes),
        'updated_at': now.toIso8601String(),
      },
      userId: _userId,
    );
    return id;
  }

  Future<String> saveScheduleRule(
    CourseScheduleRuleDraft draft, {
    String? ruleId,
  }) async {
    _validateScheduleRule(draft);
    final now = DateTime.now().toUtc();
    final id = ruleId ?? _uuid.v4();
    await _database
        .into(_database.courseScheduleRuleRecords)
        .insertOnConflictUpdate(
          CourseScheduleRuleRecordsCompanion.insert(
            id: id,
            courseId: draft.courseId,
            userId: _userId,
            weekday: draft.weekday,
            weekRuleType: draft.weekRuleType.name,
            startWeek: Value(draft.startWeek),
            endWeek: Value(draft.endWeek),
            intervalWeeks: Value(draft.intervalWeeks),
            weekNumbersJson: Value(jsonEncode(draft.weekNumbers.toList())),
            scheduleTemplateId: Value(draft.scheduleTemplateId),
            sectionIdsJson: Value(jsonEncode(draft.sectionIds)),
            startsAtMinute: draft.startsAtMinute,
            endsAtMinute: draft.endsAtMinute,
            remindBeforeMinutes: Value(draft.remindBeforeMinutes),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _syncQueue.enqueue(
      entityType: 'course_schedule_rules',
      entityId: id,
      operation: SyncOperationType.upsert,
      payload: {
        'id': id,
        'course_id': draft.courseId,
        'weekday': draft.weekday,
        'week_rule_type': draft.weekRuleType.name,
        'start_week': draft.startWeek,
        'end_week': draft.endWeek,
        'interval_weeks': draft.intervalWeeks,
        'week_numbers': draft.weekNumbers.toList(),
        'schedule_template_id': draft.scheduleTemplateId,
        'section_ids': draft.sectionIds,
        'starts_at_minute': draft.startsAtMinute,
        'ends_at_minute': draft.endsAtMinute,
        'remind_before_minutes': draft.remindBeforeMinutes,
        'updated_at': now.toIso8601String(),
      },
      userId: _userId,
    );
    return id;
  }

  Future<String> saveScheduleTemplate(
    ScheduleTemplateDraft draft, {
    String? templateId,
  }) async {
    if (draft.name.trim().isEmpty) {
      throw ArgumentError.value(draft.name, 'name', '请填写作息模板名称');
    }
    for (final segment in draft.segments) {
      _validateTimeRange(segment.startsAtMinute, segment.endsAtMinute);
    }
    final now = DateTime.now().toUtc();
    final id = templateId ?? _uuid.v4();
    await _database.transaction(() async {
      await _database
          .into(_database.scheduleTemplateRecords)
          .insertOnConflictUpdate(
            ScheduleTemplateRecordsCompanion.insert(
              id: id,
              userId: _userId,
              name: draft.name.trim(),
              timezone: Value(draft.timezone),
              isDefault: Value(draft.isDefault),
              createdAt: now,
              updatedAt: now,
            ),
          );
      if (templateId != null) {
        await (_database.delete(
          _database.scheduleTemplateSegmentRecords,
        )..where((row) => row.templateId.equals(id))).go();
      }
      for (final segment in draft.segments) {
        await _database
            .into(_database.scheduleTemplateSegmentRecords)
            .insert(
              ScheduleTemplateSegmentRecordsCompanion.insert(
                id: _uuid.v4(),
                templateId: id,
                userId: _userId,
                name: segment.name.trim(),
                startsAtMinute: segment.startsAtMinute,
                endsAtMinute: segment.endsAtMinute,
                segmentType: Value(segment.segmentType.name),
                sortOrder: Value(segment.sortOrder),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
    });
    await _syncQueue.enqueue(
      entityType: 'schedule_templates',
      entityId: id,
      operation: SyncOperationType.upsert,
      payload: {
        'id': id,
        'name': draft.name.trim(),
        'timezone': draft.timezone,
        'is_default': draft.isDefault,
        'segments': [
          for (final segment in draft.segments)
            {
              'name': segment.name.trim(),
              'starts_at_minute': segment.startsAtMinute,
              'ends_at_minute': segment.endsAtMinute,
              'segment_type': segment.segmentType.name,
              'sort_order': segment.sortOrder,
            },
        ],
        'updated_at': now.toIso8601String(),
      },
      userId: _userId,
    );
    return id;
  }

  Future<void> archiveCourse(String courseId) async {
    final now = DateTime.now().toUtc();
    await (_database.update(
          _database.courseRecords,
        )..where((row) => row.id.equals(courseId) & row.userId.equals(_userId)))
        .write(
          CourseRecordsCompanion(
            status: Value(CourseStatus.archived.name),
            updatedAt: Value(now),
            deletedAt: Value(now),
          ),
        );
    await _syncQueue.enqueue(
      entityType: 'courses',
      entityId: courseId,
      operation: SyncOperationType.archive,
      payload: {'id': courseId, 'deleted_at': now.toIso8601String()},
      userId: _userId,
    );
  }

  Future<void> archiveScheduleRule(String ruleId) async {
    final now = DateTime.now().toUtc();
    await (_database.update(_database.courseScheduleRuleRecords)
          ..where((row) => row.id.equals(ruleId) & row.userId.equals(_userId)))
        .write(
          CourseScheduleRuleRecordsCompanion(
            updatedAt: Value(now),
            deletedAt: Value(now),
          ),
        );
    await _syncQueue.enqueue(
      entityType: 'course_schedule_rules',
      entityId: ruleId,
      operation: SyncOperationType.archive,
      payload: {'id': ruleId, 'deleted_at': now.toIso8601String()},
      userId: _userId,
    );
  }

  Future<CourseDetails> _toDetails(CourseRecord row) async {
    final rules =
        await (_database.select(_database.courseScheduleRuleRecords)
              ..where(
                (rule) =>
                    rule.courseId.equals(row.id) &
                    rule.userId.equals(_userId) &
                    rule.deletedAt.isNull(),
              )
              ..orderBy([
                (rule) => OrderingTerm.asc(rule.weekday),
                (rule) => OrderingTerm.asc(rule.startsAtMinute),
              ]))
            .get();
    return CourseDetails(
      id: row.id,
      name: row.name,
      colorValue: row.colorValue,
      status: CourseStatus.values.byName(row.status),
      teacher: row.teacher,
      classroom: row.classroom,
      semester: row.semester,
      notes: row.notes,
      createdAt: row.createdAt.toLocal(),
      updatedAt: row.updatedAt.toLocal(),
      rules: rules.map(_toRule).toList(),
    );
  }

  CourseScheduleRule _toRule(CourseScheduleRuleRecord row) {
    final weeks = (jsonDecode(row.weekNumbersJson) as List).cast<int>().toSet();
    final sections = (jsonDecode(row.sectionIdsJson) as List).cast<String>();
    return CourseScheduleRule(
      id: row.id,
      courseId: row.courseId,
      weekday: row.weekday,
      weekRuleType: CourseWeekRuleType.values.byName(row.weekRuleType),
      startsAtMinute: row.startsAtMinute,
      endsAtMinute: row.endsAtMinute,
      startWeek: row.startWeek,
      endWeek: row.endWeek,
      intervalWeeks: row.intervalWeeks,
      weekNumbers: weeks,
      scheduleTemplateId: row.scheduleTemplateId,
      sectionIds: sections,
      remindBeforeMinutes: row.remindBeforeMinutes,
      createdAt: row.createdAt.toLocal(),
      updatedAt: row.updatedAt.toLocal(),
    );
  }

  void _validateScheduleRule(CourseScheduleRuleDraft draft) {
    if (draft.weekday < DateTime.monday || draft.weekday > DateTime.sunday) {
      throw ArgumentError.value(draft.weekday, 'weekday', '星期必须在 1 到 7 之间');
    }
    _validateTimeRange(draft.startsAtMinute, draft.endsAtMinute);
    if (draft.weekRuleType == CourseWeekRuleType.everyNWeeks &&
        (draft.intervalWeeks == null || draft.intervalWeeks! <= 0)) {
      throw ArgumentError.value(
        draft.intervalWeeks,
        'intervalWeeks',
        '每 N 周规则需要有效间隔',
      );
    }
    if (draft.weekRuleType == CourseWeekRuleType.custom &&
        draft.weekNumbers.isEmpty) {
      throw ArgumentError.value(draft.weekNumbers, 'weekNumbers', '请选择周次');
    }
  }

  void _validateTimeRange(int start, int end) {
    if (start < 0 || start > 1439) {
      throw ArgumentError.value(start, 'startsAtMinute', '开始时间无效');
    }
    if (end < 1 || end > 1440 || end <= start) {
      throw ArgumentError.value(end, 'endsAtMinute', '结束时间无效');
    }
  }

  String? _clean(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }
}
