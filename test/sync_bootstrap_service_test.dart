import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_bootstrap_service.dart';
import 'package:check_d/core/sync/sync_download_service.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/core/theme/app_skin.dart';
import 'package:check_d/core/theme/appearance_preferences.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const userId = 'user-1';
  late AppDatabase database;
  late SyncQueueService queue;
  late SyncBootstrapService bootstrap;
  late OfflineDataMergeService merge;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    queue = SyncQueueService(database);
    bootstrap = SyncBootstrapService(database, queue);
    merge = OfflineDataMergeService(database, queue);
  });

  tearDown(() => database.close());

  test(
    'historical authenticated entity without outbox is bootstrapped once',
    () async {
      await _insertTask(database, id: 'historical', owner: userId);

      final first = await bootstrap.bootstrap(userId);
      final second = await bootstrap.bootstrap(userId);

      expect(first.operationsCreated, 1);
      expect(second.alreadyCompleted, isTrue);
      final operations = await database.select(database.syncOperations).get();
      expect(operations, hasLength(1));
      expect(operations.single.entityType, 'tasks');
      expect(operations.single.entityId, 'historical');
    },
  );

  test(
    'bootstrap failure rolls back operations and does not write marker',
    () async {
      await _insertTask(database, id: 'historical', owner: userId);
      await database
          .into(database.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: 'reminder-defaults:$userId',
              value: '{invalid-json',
              updatedAt: DateTime.utc(2030),
            ),
          );

      await expectLater(bootstrap.bootstrap(userId), throwsFormatException);

      expect(await database.select(database.syncOperations).get(), isEmpty);
      final markers = await database
          .customSelect(
            "SELECT key FROM app_settings WHERE key LIKE 'sync-bootstrap:%'",
          )
          .get();
      expect(markers, isEmpty);
    },
  );

  test('offline data is never automatically bootstrapped', () async {
    await _insertTask(database, id: 'offline-task', owner: offlineDataOwner);

    final result = await bootstrap.bootstrap(offlineDataOwner);

    expect(result.operationsCreated, 0);
    expect(await database.select(database.syncOperations).get(), isEmpty);
    expect(
      (await database.select(database.localTasks).getSingle()).userId,
      offlineDataOwner,
    );
  });

  test('deferring offline data leaves owner and rows unchanged', () async {
    await _insertTask(database, id: 'offline-task', owner: offlineDataOwner);

    final summary = await merge.summary();

    expect(summary.tasks, 1);
    expect(
      (await database.select(database.localTasks).getSingle()).userId,
      offlineDataOwner,
    );
    expect(await database.select(database.syncOperations).get(), isEmpty);
  });

  test(
    'offline merge preserves ids, changes owner, and creates outbox',
    () async {
      await _insertTask(database, id: 'offline-task', owner: offlineDataOwner);
      await _insertLongTermGraph(database, 'offline-task', offlineDataOwner);

      final result = await merge.mergeInto(userId);

      expect(result.operationsCreated, 1);
      final task = await database.select(database.localTasks).getSingle();
      expect(task.id, 'offline-task');
      expect(task.userId, userId);
      expect(
        (await database.select(database.longTermTaskRecords).getSingle())
            .userId,
        userId,
      );
      final operation = await database
          .select(database.syncOperations)
          .getSingle();
      expect(operation.userId, userId);
      expect(operation.entityId, 'offline-task');
    },
  );

  test(
    'merge transaction failure leaves no partially migrated state',
    () async {
      await database
          .into(database.tagRecords)
          .insert(
            TagRecordsCompanion.insert(
              id: 'offline-tag',
              userId: offlineDataOwner,
              name: '标签',
              colorValue: 1,
              createdAt: DateTime.utc(2030),
              updatedAt: DateTime.utc(2030),
            ),
          );
      await _insertTask(database, id: 'offline-task', owner: offlineDataOwner);
      await database.customStatement(
        'CREATE TRIGGER stop_merge BEFORE UPDATE OF user_id ON local_tasks '
        "BEGIN SELECT RAISE(ABORT, 'stop merge'); END",
      );

      await expectLater(merge.mergeInto(userId), throwsA(anything));

      expect(
        (await database.select(database.tagRecords).getSingle()).userId,
        offlineDataOwner,
      );
      expect(
        (await database.select(database.localTasks).getSingle()).userId,
        offlineDataOwner,
      );
      expect(await database.select(database.syncOperations).get(), isEmpty);
    },
  );

  test('bootstrap never crosses owners between account A and B', () async {
    await _insertTask(database, id: 'task-a', owner: 'user-a');
    await _insertTask(database, id: 'task-b', owner: 'user-b');

    await bootstrap.bootstrap('user-b');

    final operations = await database.select(database.syncOperations).get();
    expect(operations, hasLength(1));
    expect(operations.single.userId, 'user-b');
    expect(operations.single.entityId, 'task-b');
  });

  test(
    'offline merge and bootstrap never enqueue or clear device appearance',
    () async {
      final appearance = AppearancePreferencesRepository(database);
      await appearance.save(
        const AppearancePreferences(
          skin: AppSkinId.neutral,
          icon: AppIconStyle.slate,
        ),
      );
      await _insertTask(database, id: 'offline-task', owner: offlineDataOwner);

      await merge.mergeInto(userId);
      await bootstrap.bootstrap(userId);
      await bootstrap.bootstrap('other-user');

      final operations = await database.select(database.syncOperations).get();
      expect(operations, hasLength(1));
      expect(operations.single.entityType, 'tasks');
      final saved = await appearance.load();
      expect(saved.skin, AppSkinId.neutral);
      expect(saved.icon, AppIconStyle.slate);
    },
  );

  test('offline merge aborts before mutation on remote id conflict', () async {
    await _insertTask(database, id: 'shared-id', owner: offlineDataOwner);
    final guardedMerge = OfflineDataMergeService(
      database,
      queue,
      remoteReader: _ConflictRemoteReader(),
    );

    await expectLater(
      guardedMerge.mergeInto(userId),
      throwsA(isA<OfflineDataConflict>()),
    );

    final task = await database.select(database.localTasks).getSingle();
    expect(task.userId, offlineDataOwner);
    expect(await database.select(database.syncOperations).get(), isEmpty);
  });

  test('offline merge rejects a parent owned by a third account', () async {
    final now = DateTime.utc(2030);
    await database
        .into(database.scheduleTemplateRecords)
        .insert(
          ScheduleTemplateRecordsCompanion.insert(
            id: 'foreign-template',
            userId: 'other-user',
            name: '其他账号模板',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.scheduleTemplateSegmentRecords)
        .insert(
          ScheduleTemplateSegmentRecordsCompanion.insert(
            id: 'offline-segment',
            templateId: 'foreign-template',
            userId: offlineDataOwner,
            name: '跨账号关联',
            startsAtMinute: 480,
            endsAtMinute: 540,
            createdAt: now,
            updatedAt: now,
          ),
        );

    await expectLater(
      merge.mergeInto(userId),
      throwsA(isA<OfflineDataConflict>()),
    );

    final segment = await database
        .select(database.scheduleTemplateSegmentRecords)
        .getSingle();
    expect(segment.userId, offlineDataOwner);
    expect(await database.select(database.syncOperations).get(), isEmpty);
  });

  for (final (reference, table) in [
    ('daily override', 'daily_item_override_records'),
    ('reminder', 'reminder_rule_records'),
    ('alarm', 'alarm_rule_records'),
    ('task revision', 'task_revision_records'),
  ]) {
    test('offline merge rejects an account-A parent for $reference', () async {
      await _insertTask(database, id: 'foreign-task', owner: 'account-a');
      await _insertTask(database, id: 'offline-task', owner: offlineDataOwner);
      await _insertScheduleReference(
        database,
        table: table,
        parentId: 'foreign-task',
      );

      await expectLater(
        merge.mergeInto(userId),
        throwsA(isA<OfflineDataConflict>()),
      );

      await _expectUnchangedOfflineReference(database, table);
    });
  }

  test(
    'offline merge rejects a reminder linked to a task with no account',
    () async {
      await _insertTask(database, id: 'unowned-task', owner: null);
      await _insertTask(database, id: 'offline-task', owner: offlineDataOwner);
      await _insertScheduleReference(
        database,
        table: 'reminder_rule_records',
        parentId: 'unowned-task',
      );

      await expectLater(
        merge.mergeInto(userId),
        throwsA(isA<OfflineDataConflict>()),
      );

      await _expectUnchangedOfflineReference(database, 'reminder_rule_records');
    },
  );

  test(
    'offline merge rejects a destination reminder linked to offline data',
    () async {
      await _insertTask(database, id: 'offline-task', owner: offlineDataOwner);
      await _insertScheduleReference(
        database,
        table: 'reminder_rule_records',
        parentId: 'offline-task',
        childOwner: userId,
      );

      await expectLater(
        merge.mergeInto(userId),
        throwsA(isA<OfflineDataConflict>()),
      );
      expect(
        (await database.select(database.localTasks).getSingle()).userId,
        offlineDataOwner,
      );
      expect(
        (await database.select(database.reminderRuleRecords).getSingle())
            .userId,
        userId,
      );
      expect(await database.select(database.syncOperations).get(), isEmpty);
    },
  );

  for (final (sectionOwner, sectionTemplateId, expectedConflict) in [
    ('account-a', 'offline-template', 'other account'),
    (offlineDataOwner, 'different-template', 'different template'),
  ]) {
    test(
      'offline merge rejects a course section from $expectedConflict',
      () async {
        await _insertTask(
          database,
          id: 'offline-task',
          owner: offlineDataOwner,
        );
        await _insertCourseGraph(
          database,
          sectionOwner: sectionOwner,
          sectionTemplateId: sectionTemplateId,
        );

        await expectLater(
          merge.mergeInto(userId),
          throwsA(isA<OfflineDataConflict>()),
        );

        await _expectUnchangedOfflineReference(
          database,
          'course_schedule_rule_records',
        );
      },
    );
  }

  test(
    'offline merge preserves owned rule references and local task history',
    () async {
      await _insertTask(database, id: 'offline-task', owner: offlineDataOwner);
      await _insertCourseGraph(database);
      await _insertScheduleReference(
        database,
        table: 'daily_item_override_records',
        parentId: 'offline-rule',
        type: 'course',
      );
      await _insertScheduleReference(
        database,
        table: 'reminder_rule_records',
        parentId: 'offline-rule',
        type: 'course',
      );
      await _insertScheduleReference(
        database,
        table: 'alarm_rule_records',
        parentId: 'offline-course',
        type: 'course',
      );
      await _insertScheduleReference(
        database,
        table: 'task_revision_records',
        parentId: 'offline-task',
      );

      await merge.mergeInto(userId);

      expect(
        (await database.select(database.courseScheduleRuleRecords).getSingle())
            .sectionIdsJson,
        '["section"]',
      );
      expect(
        (await database.select(database.dailyItemOverrideRecords).getSingle())
            .userId,
        userId,
      );
      expect(
        (await database.select(database.reminderRuleRecords).getSingle())
            .userId,
        userId,
      );
      expect(
        (await database.select(database.alarmRuleRecords).getSingle()).userId,
        userId,
      );
      final revision = await database
          .select(database.taskRevisionRecords)
          .getSingle();
      expect(revision.userId, userId);
      expect(revision.taskId, 'offline-task');
      final outbox = await database.select(database.syncOperations).get();
      expect(
        outbox.map((op) => op.entityType),
        containsAll([
          'daily_item_overrides',
          'reminder_rules',
          'alarm_rules',
          'course_schedule_rules',
        ]),
      );
      expect(outbox.map((op) => op.entityId), isNot(contains(revision.id)));
    },
  );
}

Future<void> _expectUnchangedOfflineReference(
  AppDatabase database,
  String table,
) async {
  final child = await database
      .customSelect('SELECT user_id FROM $table')
      .getSingle();
  expect(child.read<String>('user_id'), offlineDataOwner);
  final task = await (database.select(
    database.localTasks,
  )..where((row) => row.id.equals('offline-task'))).getSingle();
  expect(task.userId, offlineDataOwner);
  expect(await database.select(database.syncOperations).get(), isEmpty);
}

Future<void> _insertScheduleReference(
  AppDatabase database, {
  required String table,
  required String parentId,
  String childOwner = offlineDataOwner,
  String type = 'recurring',
}) async {
  final now = DateTime.utc(2030);
  switch (table) {
    case 'daily_item_override_records':
      await database
          .into(database.dailyItemOverrideRecords)
          .insert(
            DailyItemOverrideRecordsCompanion.insert(
              id: 'override',
              userId: childOwner,
              itemType: type,
              itemId: parentId,
              localDate: '2030-01-01',
              action: 'skip',
              createdAt: now,
              updatedAt: now,
            ),
          );
    case 'reminder_rule_records':
      await database
          .into(database.reminderRuleRecords)
          .insert(
            ReminderRuleRecordsCompanion.insert(
              id: 'reminder',
              userId: childOwner,
              ownerType: type,
              ownerId: parentId,
              reminderKind: 'due',
              createdAt: now,
              updatedAt: now,
            ),
          );
    case 'alarm_rule_records':
      await database
          .into(database.alarmRuleRecords)
          .insert(
            AlarmRuleRecordsCompanion.insert(
              id: 'alarm',
              userId: childOwner,
              ownerType: type,
              ownerId: parentId,
              createdAt: now,
              updatedAt: now,
            ),
          );
    case 'task_revision_records':
      await database
          .into(database.taskRevisionRecords)
          .insert(
            TaskRevisionRecordsCompanion.insert(
              id: 'revision',
              userId: childOwner,
              taskId: parentId,
              afterJson: '{}',
              changedAt: now,
            ),
          );
    default:
      throw ArgumentError.value(table, 'table');
  }
}

Future<void> _insertCourseGraph(
  AppDatabase database, {
  String sectionOwner = offlineDataOwner,
  String sectionTemplateId = 'offline-template',
}) async {
  final now = DateTime.utc(2030);
  for (final templateId in {'offline-template', sectionTemplateId}) {
    await database
        .into(database.scheduleTemplateRecords)
        .insert(
          ScheduleTemplateRecordsCompanion.insert(
            id: templateId,
            userId: offlineDataOwner,
            name: templateId,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }
  await database
      .into(database.scheduleTemplateSegmentRecords)
      .insert(
        ScheduleTemplateSegmentRecordsCompanion.insert(
          id: 'section',
          templateId: sectionTemplateId,
          userId: sectionOwner,
          name: '第1节',
          startsAtMinute: 480,
          endsAtMinute: 540,
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.courseRecords)
      .insert(
        CourseRecordsCompanion.insert(
          id: 'offline-course',
          userId: offlineDataOwner,
          name: '离线课程',
          colorValue: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.courseScheduleRuleRecords)
      .insert(
        CourseScheduleRuleRecordsCompanion.insert(
          id: 'offline-rule',
          userId: offlineDataOwner,
          courseId: 'offline-course',
          weekday: 1,
          weekRuleType: 'everyWeek',
          scheduleTemplateId: const Value('offline-template'),
          sectionIdsJson: const Value('["section"]'),
          timeMode: const Value('periods'),
          startsAtMinute: 480,
          endsAtMinute: 540,
          createdAt: now,
          updatedAt: now,
        ),
      );
}

class _ConflictRemoteReader implements SyncRemoteReader {
  @override
  Future<List<Map<String, Object?>>> readTable(
    String table, {
    required String userId,
  }) async {
    if (table != 'tasks') return const [];
    return [
      {'id': 'shared-id', 'user_id': userId},
    ];
  }
}

Future<void> _insertTask(
  AppDatabase database, {
  required String id,
  required String? owner,
}) {
  final now = DateTime.utc(2030);
  return database
      .into(database.localTasks)
      .insert(
        LocalTasksCompanion.insert(
          id: id,
          userId: Value(owner),
          name: id,
          taskType: 'recurring',
          colorValue: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<void> _insertLongTermGraph(
  AppDatabase database,
  String taskId,
  String owner,
) async {
  final now = DateTime.utc(2030);
  await database
      .into(database.longTermTaskRecords)
      .insert(
        LongTermTaskRecordsCompanion.insert(
          taskId: taskId,
          userId: owner,
          checkMode: 'timed',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.taskScheduleRecords)
      .insert(
        TaskScheduleRecordsCompanion.insert(
          id: 'schedule-$taskId',
          taskId: taskId,
          userId: owner,
          scheduleType: 'daily',
          weekdaysMask: 127,
          startsOn: '2030-01-01',
          createdAt: now,
          updatedAt: now,
        ),
      );
}
