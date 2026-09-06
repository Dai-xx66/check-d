import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/profile/data/reminder_defaults_repository.dart';
import 'package:check_d/features/schedule/data/day_schedule_repository.dart';
import 'package:check_d/features/schedule/domain/day_schedule_models.dart';
import 'package:check_d/shared/utils/app_time.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test(
    'reminder defaults persist per user without changing saved rules',
    () async {
      final defaults = ReminderDefaultsRepository(
        database: database,
        userId: 'student-a',
      );
      final otherUserDefaults = ReminderDefaultsRepository(
        database: database,
        userId: 'student-b',
      );
      final schedule = DayScheduleRepository(
        database: database,
        syncQueue: SyncQueueService(database),
        userId: 'student-a',
      );
      await schedule.replaceReminderConfiguration(
        ownerType: DayItemType.oneTime,
        ownerId: 'existing-item',
        advanceEnabled: true,
        advanceMinutes: 10,
        atTimeEnabled: false,
      );

      expect(await defaults.load(), const ReminderDefaults());
      await defaults.save(
        const ReminderDefaults(
          advanceEnabled: true,
          advanceMinutes: 15,
          atTimeEnabled: true,
        ),
      );

      expect(
        await defaults.load(),
        isA<ReminderDefaults>()
            .having((value) => value.advanceEnabled, 'advance enabled', true)
            .having((value) => value.advanceMinutes, 'advance minutes', 15)
            .having((value) => value.atTimeEnabled, 'at-time enabled', true),
      );
      expect(await otherUserDefaults.load(), const ReminderDefaults());

      final existing = await schedule.loadReminderRules();
      final advance = existing.firstWhere(
        (rule) => rule.reminderKind == ReminderKind.advance,
      );
      final due = existing.firstWhere(
        (rule) => rule.reminderKind == ReminderKind.due,
      );
      expect(advance.enabled, isTrue);
      expect(advance.remindBeforeMinutes, 10);
      expect(due.enabled, isFalse);
    },
  );

  testWidgets('time helper forces 24-hour picker media settings', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => appTimePickerBuilder(
            context,
            Builder(
              builder: (context) => Text(
                MediaQuery.of(context).alwaysUse24HourFormat ? '24h' : '12h',
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('24h'), findsOneWidget);
    expect(formatAppTime(8 * 60), '08:00');
    expect(formatAppTime(14 * 60 + 30), '14:30');
    expect(formatAppTime(20 * 60 + 5), '20:05');
  });
}
