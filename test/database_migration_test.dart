import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:check_d/core/database/app_database.dart';

void main() {
  test(
    'v20 to v21 preserves queued operations and adds device generations',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'check_d_sync_generation_migration_',
      );
      final file = File('${directory.path}/check_d.sqlite');
      final legacy = AppDatabase.forTesting(NativeDatabase(file));
      final now = DateTime.utc(2026, 11, 16);
      try {
        await legacy
            .into(legacy.syncOperations)
            .insert(
              SyncOperationsCompanion.insert(
                id: 'pending-1',
                userId: const Value('user-1'),
                entityType: 'tasks',
                entityId: 'task-1',
                operation: 'upsert',
                payloadJson: '{"id":"task-1"}',
                createdAt: now,
                updatedAt: now,
              ),
            );
        await legacy.customStatement(
          'ALTER TABLE sync_operations DROP COLUMN local_generation',
        );
        await legacy.customStatement('DROP TABLE sync_device_states');
        await legacy.customStatement('PRAGMA user_version = 20');
        await legacy.close();

        final upgraded = AppDatabase.forTesting(NativeDatabase(file));
        try {
          final queued = await (upgraded.select(
            upgraded.syncOperations,
          )..where((row) => row.id.equals('pending-1'))).getSingle();
          expect(queued.status, 'pending');
          expect(queued.localGeneration, isNull);
          expect(
            await upgraded.select(upgraded.syncDeviceStates).get(),
            isEmpty,
          );
          final info = await upgraded
              .customSelect('PRAGMA table_info(sync_operations)')
              .get();
          expect(
            info.any((row) => row.read<String>('name') == 'local_generation'),
            isTrue,
          );
        } finally {
          await upgraded.close();
        }
      } finally {
        await legacy.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'v19 to v20 preserves old one-time dates without inventing deadlines',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'check_d_stage_14a_migration_',
      );
      final file = File('${directory.path}/check_d.sqlite');
      final now = DateTime.utc(2026, 9, 15);
      final scheduled = DateTime.utc(2026, 9, 20, 8, 30);
      final legacy = AppDatabase.forTesting(NativeDatabase(file));

      try {
        for (final id in ['scheduled', 'unscheduled']) {
          await legacy
              .into(legacy.localTasks)
              .insert(
                LocalTasksCompanion.insert(
                  id: id,
                  userId: const Value('user-1'),
                  name: id,
                  taskType: 'oneTime',
                  colorValue: 1,
                  createdAt: now,
                  updatedAt: now,
                ),
              );
        }
        await legacy
            .into(legacy.oneTimeReminderRecords)
            .insert(
              OneTimeReminderRecordsCompanion.insert(
                taskId: 'scheduled',
                userId: 'user-1',
                scheduledAt: scheduled,
                hasScheduledDate: const Value(true),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await legacy
            .into(legacy.oneTimeReminderRecords)
            .insert(
              OneTimeReminderRecordsCompanion.insert(
                taskId: 'unscheduled',
                userId: 'user-1',
                scheduledAt: now,
                hasScheduledDate: const Value(false),
                createdAt: now,
                updatedAt: now,
              ),
            );
        for (final column in [
          'available_from',
          'planned_date',
          'due_date',
          'due_at',
        ]) {
          await legacy.customStatement(
            'ALTER TABLE one_time_reminder_records DROP COLUMN $column',
          );
        }
        await legacy.customStatement('PRAGMA user_version = 19');
        await legacy.close();

        final upgraded = AppDatabase.forTesting(NativeDatabase(file));
        try {
          final rows = await (upgraded.select(
            upgraded.oneTimeReminderRecords,
          )..orderBy([(row) => OrderingTerm.asc(row.taskId)])).get();
          final scheduledRow = rows.singleWhere(
            (row) => row.taskId == 'scheduled',
          );
          final unscheduledRow = rows.singleWhere(
            (row) => row.taskId == 'unscheduled',
          );

          expect(scheduledRow.hasScheduledDate, isTrue);
          expect(scheduledRow.scheduledAt.isAtSameMomentAs(scheduled), isTrue);
          expect(unscheduledRow.hasScheduledDate, isFalse);
          expect(unscheduledRow.scheduledAt.isAtSameMomentAs(now), isTrue);
          for (final row in rows) {
            expect(row.availableFrom, isNull);
            expect(row.plannedDate, isNull);
            expect(row.dueDate, isNull);
            expect(row.dueAt, isNull);
          }
        } finally {
          await upgraded.close();
        }
      } finally {
        if (await file.exists()) {
          try {
            await legacy.close();
          } catch (_) {}
        }
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'latest-version database missing Multi Timer intervals self-heals without data loss',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'check_d_migration_',
      );
      final file = File('${directory.path}/check_d.sqlite');
      final first = AppDatabase.forTesting(NativeDatabase(file));
      final now = DateTime.now().toUtc();
      await first
          .into(first.courseRecords)
          .insert(
            CourseRecordsCompanion.insert(
              id: 'course-1',
              userId: 'user-1',
              name: '高等数学',
              colorValue: 1,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await first
          .into(first.adHocTimerRecords)
          .insert(
            AdHocTimerRecordsCompanion.insert(
              id: 'timer-1',
              userId: 'user-1',
              title: '旧计时',
              colorValue: 1,
              startedAt: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await first.customStatement('DROP TABLE ad_hoc_timer_interval_records');
      // Model the real Web failure: schema version is already current even
      // though an earlier release omitted this table.
      await first.customStatement('PRAGMA user_version = 19');
      await first.close();

      final upgraded = AppDatabase.forTesting(NativeDatabase(file));
      await upgraded
          .customSelect('SELECT 1 FROM ad_hoc_timer_interval_records')
          .get();
      expect(
        (await (upgraded.select(
          upgraded.courseRecords,
        )..where((row) => row.id.equals('course-1'))).getSingle()).name,
        '高等数学',
      );
      await upgraded
          .into(upgraded.adHocTimerIntervalRecords)
          .insert(
            AdHocTimerIntervalRecordsCompanion.insert(
              id: 'interval-1',
              timerId: 'timer-1',
              userId: 'user-1',
              startedAt: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      expect(
        await (upgraded.select(
          upgraded.adHocTimerIntervalRecords,
        )..where((row) => row.timerId.equals('timer-1'))).get(),
        hasLength(1),
      );
      await upgraded.close();
      await directory.delete(recursive: true);
    },
  );
}
