import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:check_d/core/database/app_database.dart';

void main() {
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
