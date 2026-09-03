import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/plans/data/plan_repository.dart';
import 'package:check_d/features/plans/domain/plan_models.dart';
import 'package:check_d/features/tasks/data/task_repository.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late TaskRepository tasks;
  late PlanRepository plans;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    final queue = SyncQueueService(database);
    tasks = TaskRepository(database: database, syncQueue: queue, userId: 'u1');
    plans = PlanRepository(database: database, syncQueue: queue, userId: 'u1');
  });

  tearDown(() => database.close());

  test(
    'plan progress is calculated from linked recurring task completions',
    () async {
      final today = dateOnly(DateTime.now());
      final startsOn = today.subtract(const Duration(days: 2));
      final taskId = await tasks.saveRecurringTask(
        RecurringTaskDraft(
          name: '每日阅读',
          colorValue: 0xFF3D73E8,
          executionMode: RecurringExecutionMode.untimed,
          schedulePreset: SchedulePreset.daily,
          weekdays: WeekdayMask.toDays(WeekdayMask.everyDay),
          startsOn: startsOn,
          holidayPause: false,
        ),
      );
      await tasks.toggleRecurringCompletion(taskId, startsOn);
      await tasks.toggleRecurringCompletion(taskId, today);

      await plans.save(
        PlanDraft(
          name: '本周阅读',
          type: PlanType.month,
          colorValue: 0xFF3D73E8,
          startsOn: startsOn,
          endsOn: today,
          taskIds: {taskId},
        ),
      );

      final plan = (await plans.watchPlans().first).single;
      expect(plan.taskIds, {taskId});
      expect(plan.dueCount, 3);
      expect(plan.completedCount, 2);
      expect(plan.progressPercent, 67);
    },
  );

  test(
    'plan data validation rejects blank names and unrelated task types',
    () async {
      final today = dateOnly(DateTime.now());
      await expectLater(
        plans.save(
          PlanDraft(
            name: ' ',
            type: PlanType.month,
            colorValue: 1,
            startsOn: today,
            endsOn: today,
            taskIds: const {},
          ),
        ),
        throwsArgumentError,
      );
      final reminderId = await tasks.saveOneTimeReminder(
        OneTimeReminderDraft(name: '会议', colorValue: 1, scheduledAt: today),
      );
      await expectLater(
        plans.save(
          PlanDraft(
            name: '无效关联',
            type: PlanType.month,
            colorValue: 1,
            startsOn: today,
            endsOn: today,
            taskIds: {reminderId},
          ),
        ),
        throwsArgumentError,
      );
    },
  );
}
