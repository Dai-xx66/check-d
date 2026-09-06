import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/sync/sync_queue_service.dart';
import '../domain/course_models.dart';

class CourseRepository {
  CourseRepository({
    required AppDatabase database,
    required SyncQueueService syncQueue,
    required String userId,
    NotificationService? notifications,
  }) : _database = database,
       _syncQueue = syncQueue,
       _userId = userId,
       _notifications = notifications;

  final AppDatabase _database;
  final SyncQueueService _syncQueue;
  final String _userId;
  final NotificationService? _notifications;
  final Uuid _uuid = const Uuid();

  Stream<List<CourseDetails>> watchCourses() async* {
    final query = _database.select(_database.courseRecords)
      ..where(
        (row) =>
            row.userId.equals(_userId) &
            row.deletedAt.isNull() &
            row.status.equals(CourseStatus.active.name),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.name)]);
    Future<List<CourseDetails>> load(List<CourseRecord> rows) =>
        Future.wait(rows.map(_toDetails));

    yield await load(await query.get());
    yield* query.watch().asyncMap(load);
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
            semesterId: Value(draft.semesterId),
            semesterStartsOn: Value(_dateOnlyUtc(draft.semesterStartsOn)),
            semesterEndsOn: Value(_dateOnlyUtc(draft.semesterEndsOn)),
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
        'semester_id': draft.semesterId,
        'semester_starts_on': _dateOnlyUtc(
          draft.semesterStartsOn,
        )?.toIso8601String(),
        'semester_ends_on': _dateOnlyUtc(
          draft.semesterEndsOn,
        )?.toIso8601String(),
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
    await _cancelReminder(id);
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
    await _syncReminder(id, draft);
    return id;
  }

  Future<String> saveScheduleTemplate(
    ScheduleTemplateDraft draft, {
    String? templateId,
  }) async {
    if (draft.name.trim().isEmpty) {
      throw ArgumentError.value(draft.name, 'name', '请填写作息模板名称');
    }
    final segments = [...draft.segments]
      ..sort((a, b) => a.startsAtMinute.compareTo(b.startsAtMinute));
    for (final segment in segments) {
      _validateTimeRange(segment.startsAtMinute, segment.endsAtMinute);
    }
    for (var index = 1; index < segments.length; index++) {
      final previous = segments[index - 1];
      final current = segments[index];
      if (current.startsAtMinute < previous.endsAtMinute) {
        throw ArgumentError(
          '“${current.name.trim().isEmpty ? '第${index + 1}节' : current.name}”与“${previous.name.trim().isEmpty ? '第$index节' : previous.name}”时间重叠',
        );
      }
    }
    final now = DateTime.now().toUtc();
    final id = templateId ?? _uuid.v4();
    late List<ScheduleTemplateSegmentDraft> savedSegments;
    await _database.transaction(() async {
      final existingSegments = templateId == null
          ? const <ScheduleTemplateSegmentRecord>[]
          : await (_database.select(_database.scheduleTemplateSegmentRecords)
                  ..where(
                    (row) => row.templateId.equals(id) & row.deletedAt.isNull(),
                  )
                  ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]))
                .get();
      final legacySegments = existingSegments
          .where(
            (segment) =>
                segment.segmentType != ScheduleSegmentType.classTime.name,
          )
          .map(
            (segment) => ScheduleTemplateSegmentDraft(
              id: segment.id,
              name: segment.name,
              startsAtMinute: segment.startsAtMinute,
              endsAtMinute: segment.endsAtMinute,
              segmentType: ScheduleSegmentType.values.byName(
                segment.segmentType,
              ),
              sortOrder: segment.sortOrder,
            ),
          );
      final persistedSegments = [...segments, ...legacySegments]
        ..sort((a, b) => a.startsAtMinute.compareTo(b.startsAtMinute));
      savedSegments = [
        for (final segment in persistedSegments)
          ScheduleTemplateSegmentDraft(
            id: segment.id ?? _uuid.v4(),
            name: segment.name,
            startsAtMinute: segment.startsAtMinute,
            endsAtMinute: segment.endsAtMinute,
            segmentType: segment.segmentType,
            sortOrder: segment.sortOrder,
          ),
      ];
      for (var index = 1; index < persistedSegments.length; index++) {
        final previous = persistedSegments[index - 1];
        final current = persistedSegments[index];
        if (current.startsAtMinute < previous.endsAtMinute) {
          throw ArgumentError('节次时间不能与现有休息时段重叠');
        }
      }
      final retainedSegmentIds = savedSegments
          .map((segment) => segment.id)
          .whereType<String>()
          .toSet();
      if (templateId != null) {
        final rules =
            await (_database.select(_database.courseScheduleRuleRecords)..where(
                  (row) =>
                      row.userId.equals(_userId) &
                      row.scheduleTemplateId.equals(id) &
                      row.deletedAt.isNull(),
                ))
                .get();
        final referencedIds = rules
            .expand(
              (rule) =>
                  (jsonDecode(rule.sectionIdsJson) as List).cast<String>(),
            )
            .toSet();
        if (!referencedIds.every(retainedSegmentIds.contains)) {
          throw StateError('该模板节次正在被课程安排使用，请先调整课程安排。');
        }
      }
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
      if (draft.isDefault) {
        await (_database.update(_database.scheduleTemplateRecords)..where(
              (row) =>
                  row.userId.equals(_userId) &
                  row.id.equals(id).not() &
                  row.deletedAt.isNull(),
            ))
            .write(
              ScheduleTemplateRecordsCompanion(
                isDefault: const Value(false),
                updatedAt: Value(now),
              ),
            );
      }
      if (templateId != null) {
        await (_database.delete(
          _database.scheduleTemplateSegmentRecords,
        )..where((row) => row.templateId.equals(id))).go();
      }
      for (var index = 0; index < savedSegments.length; index++) {
        final segment = savedSegments[index];
        await _database
            .into(_database.scheduleTemplateSegmentRecords)
            .insert(
              ScheduleTemplateSegmentRecordsCompanion.insert(
                id: segment.id!,
                templateId: id,
                userId: _userId,
                name: segment.name.trim(),
                startsAtMinute: segment.startsAtMinute,
                endsAtMinute: segment.endsAtMinute,
                segmentType: Value(segment.segmentType.name),
                sortOrder: Value(index),
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
          for (var index = 0; index < savedSegments.length; index++)
            {
              'id': savedSegments[index].id,
              'name': savedSegments[index].name.trim(),
              'starts_at_minute': savedSegments[index].startsAtMinute,
              'ends_at_minute': savedSegments[index].endsAtMinute,
              'segment_type': savedSegments[index].segmentType.name,
              'sort_order': index,
            },
        ],
        'updated_at': now.toIso8601String(),
      },
      userId: _userId,
    );
    return id;
  }

  Stream<List<ScheduleTemplateDetails>> watchScheduleTemplates() async* {
    final query = _database.select(_database.scheduleTemplateRecords)
      ..where((row) => row.userId.equals(_userId) & row.deletedAt.isNull())
      ..orderBy([
        (row) => OrderingTerm.desc(row.isDefault),
        (row) => OrderingTerm.asc(row.name),
      ]);
    Future<List<ScheduleTemplateDetails>> load(
      List<ScheduleTemplateRecord> rows,
    ) => Future.wait(rows.map(_toTemplateDetails));

    yield await load(await query.get());
    yield* query.watch().asyncMap(load);
  }

  Future<ScheduleTemplateDetails?> loadScheduleTemplate(String templateId) {
    return (_database.select(_database.scheduleTemplateRecords)..where(
          (row) =>
              row.id.equals(templateId) &
              row.userId.equals(_userId) &
              row.deletedAt.isNull(),
        ))
        .getSingleOrNull()
        .then((row) => row == null ? null : _toTemplateDetails(row));
  }

  Future<void> archiveScheduleTemplate(String templateId) async {
    final usedBySemester =
        await (_database.select(_database.semesterRecords)..where(
              (row) =>
                  row.userId.equals(_userId) &
                  row.scheduleTemplateId.equals(templateId) &
                  row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (usedBySemester != null) {
      throw StateError('该作息模板正在被学期使用，请先更换学期作息模板。');
    }
    final usedByRule =
        await (_database.select(_database.courseScheduleRuleRecords)..where(
              (row) =>
                  row.userId.equals(_userId) &
                  row.scheduleTemplateId.equals(templateId) &
                  row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (usedByRule != null) {
      throw StateError('该作息模板正在被课程安排使用，请先更换课程安排的作息模板。');
    }
    final now = DateTime.now().toUtc();
    await (_database.update(_database.scheduleTemplateRecords)..where(
          (row) => row.id.equals(templateId) & row.userId.equals(_userId),
        ))
        .write(
          ScheduleTemplateRecordsCompanion(
            deletedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    await _syncQueue.enqueue(
      entityType: 'schedule_templates',
      entityId: templateId,
      operation: SyncOperationType.archive,
      payload: {'id': templateId, 'deleted_at': now.toIso8601String()},
      userId: _userId,
    );
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
    await _cancelReminder(ruleId);
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

  Future<void> _syncReminder(
    String ruleId,
    CourseScheduleRuleDraft draft,
  ) async {
    final minutes = draft.remindBeforeMinutes;
    final notifications = _notifications;
    if (notifications == null || minutes == null) return;
    final reminderMinute = draft.startsAtMinute - minutes;
    if (reminderMinute < 0) return;
    try {
      final course =
          await (_database.select(_database.courseRecords)..where(
                (row) =>
                    row.id.equals(draft.courseId) & row.userId.equals(_userId),
              ))
              .getSingleOrNull();
      await notifications.requestPermissions();
      final title = '课程提醒：${course?.name ?? '课程'}';
      final body = '课程将在 $minutes 分钟后开始';
      final semesterStart = course?.semesterStartsOn == null
          ? null
          : DateTime(
              course!.semesterStartsOn!.toLocal().year,
              course.semesterStartsOn!.toLocal().month,
              course.semesterStartsOn!.toLocal().day,
            );
      final semesterEnd = course?.semesterEndsOn == null
          ? null
          : DateTime(
              course!.semesterEndsOn!.toLocal().year,
              course.semesterEndsOn!.toLocal().month,
              course.semesterEndsOn!.toLocal().day,
            );
      final isUnboundedEveryWeek =
          draft.weekRuleType == CourseWeekRuleType.everyWeek &&
          draft.startWeek == null &&
          draft.endWeek == null &&
          semesterStart == null &&
          semesterEnd == null;
      if (isUnboundedEveryWeek) {
        await notifications.scheduleWeekly(
          id: _notificationId(ruleId),
          weekday: draft.weekday,
          minuteOfDay: reminderMinute,
          title: title,
          body: body,
        );
      } else {
        // The notification plugin cannot express odd/even or bounded weeks.
        // Schedule the next year of matching occurrences instead.
        final today = DateTime.now();
        var occurrence = DateTime(today.year, today.month, today.day);
        var scheduledCount = 0;
        for (var offset = 0; offset < 366; offset++) {
          final date = occurrence.add(Duration(days: offset));
          final dateOnly = DateTime(date.year, date.month, date.day);
          if ((semesterStart != null && dateOnly.isBefore(semesterStart)) ||
              (semesterEnd != null && dateOnly.isAfter(semesterEnd))) {
            continue;
          }
          if (date.weekday != draft.weekday ||
              !_isDueInWeek(draft, _isoWeekNumber(date))) {
            continue;
          }
          final when = DateTime(
            date.year,
            date.month,
            date.day,
            reminderMinute ~/ 60,
            reminderMinute % 60,
          );
          if (!when.isAfter(DateTime.now())) continue;
          await notifications.scheduleAt(
            id: _notificationId(ruleId, scheduledCount + 1),
            when: when,
            title: title,
            body: body,
          );
          scheduledCount++;
        }
      }
    } catch (_) {
      // Notification permission or platform scheduling failures must not block saving.
    }
  }

  Future<void> _cancelReminder(String ruleId) async {
    final notifications = _notifications;
    if (notifications == null) return;
    try {
      for (var variant = 0; variant <= 366; variant++) {
        await notifications.cancel(_notificationId(ruleId, variant));
      }
    } catch (_) {}
  }

  int _notificationId(String value, [int variant = 0]) {
    var hash = 0x811c9dc5;
    for (final codeUnit in '$value:$variant'.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  bool _isDueInWeek(CourseScheduleRuleDraft draft, int weekNumber) {
    if (weekNumber <= 0) return false;
    if (draft.startWeek != null && weekNumber < draft.startWeek!) return false;
    if (draft.endWeek != null && weekNumber > draft.endWeek!) return false;
    return switch (draft.weekRuleType) {
      CourseWeekRuleType.everyWeek => true,
      CourseWeekRuleType.oddWeeks => weekNumber.isOdd,
      CourseWeekRuleType.evenWeeks => weekNumber.isEven,
      CourseWeekRuleType.everyNWeeks =>
        (weekNumber - (draft.startWeek ?? 1)) % (draft.intervalWeeks ?? 1) == 0,
      CourseWeekRuleType.custom => draft.weekNumbers.contains(weekNumber),
    };
  }

  int _isoWeekNumber(DateTime date) {
    final thursday = DateTime(
      date.year,
      date.month,
      date.day,
    ).add(Duration(days: 4 - date.weekday));
    final firstThursday = DateTime(thursday.year, 1, 4);
    final firstMonday = firstThursday.subtract(
      Duration(days: firstThursday.weekday - 1),
    );
    return (DateTime(thursday.year, thursday.month, thursday.day)
                .difference(
                  DateTime(
                    firstMonday.year,
                    firstMonday.month,
                    firstMonday.day,
                  ),
                )
                .inDays ~/
            7) +
        1;
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
      semesterId: row.semesterId,
      semesterStartsOn: row.semesterStartsOn?.toLocal(),
      semesterEndsOn: row.semesterEndsOn?.toLocal(),
      notes: row.notes,
      createdAt: row.createdAt.toLocal(),
      updatedAt: row.updatedAt.toLocal(),
      rules: rules.map(_toRule).toList(),
    );
  }

  Future<ScheduleTemplateDetails> _toTemplateDetails(
    ScheduleTemplateRecord row,
  ) async {
    final segments =
        await (_database.select(_database.scheduleTemplateSegmentRecords)
              ..where(
                (segment) =>
                    segment.templateId.equals(row.id) &
                    segment.userId.equals(_userId) &
                    segment.deletedAt.isNull(),
              )
              ..orderBy([(segment) => OrderingTerm.asc(segment.sortOrder)]))
            .get();
    return ScheduleTemplateDetails(
      id: row.id,
      name: row.name,
      timezone: row.timezone,
      isDefault: row.isDefault,
      createdAt: row.createdAt.toLocal(),
      updatedAt: row.updatedAt.toLocal(),
      segments: segments
          .map(
            (segment) => ScheduleTemplateSegment(
              id: segment.id,
              templateId: segment.templateId,
              name: segment.name,
              startsAtMinute: segment.startsAtMinute,
              endsAtMinute: segment.endsAtMinute,
              segmentType: ScheduleSegmentType.values.byName(
                segment.segmentType,
              ),
              sortOrder: segment.sortOrder,
              createdAt: segment.createdAt.toLocal(),
              updatedAt: segment.updatedAt.toLocal(),
            ),
          )
          .toList(),
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

  DateTime? _dateOnlyUtc(DateTime? value) {
    if (value == null) return null;
    return DateTime.utc(value.year, value.month, value.day);
  }
}
