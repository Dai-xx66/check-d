import 'dart:async';

import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/plans/data/plan_repository.dart';
import 'package:check_d/features/plans/domain/plan_models.dart';
import 'package:check_d/features/tasks/data/task_repository.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Future<PlanDetails> _nextMatchingPlan(
  StreamIterator<List<PlanDetails>> updates,
  bool Function(PlanDetails) matches,
) => (() async {
  while (await updates.moveNext()) {
    final plan = updates.current.single;
    if (matches(plan)) return plan;
  }
  throw StateError('Plan stream ended before the expected progress update');
})().timeout(const Duration(seconds: 5));

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

  test('an existing plan subscription follows completion and its cancellation',
      () async {
    final today = dateOnly(DateTime.now());
    final taskId = await tasks.saveRecurringTask(
      RecurringTaskDraft(
        name: '每日阅读',
        colorValue: 1,
        executionMode: RecurringExecutionMode.untimed,
        schedulePreset: SchedulePreset.daily,
        weekdays: WeekdayMask.toDays(WeekdayMask.everyDay),
        startsOn: today,
        holidayPause: false,
      ),
    );
    await plans.save(
      PlanDraft(
        name: '今天的阅读',
        type: PlanType.month,
        colorValue: 1,
        startsOn: today,
        endsOn: today,
        taskIds: {taskId},
      ),
    );
    final updates = StreamIterator(plans.watchPlans());
    addTearDown(updates.cancel);
    final initial = await _nextMatchingPlan(updates, (_) => true);
    expect(initial.dueCount, 1);
    expect(initial.completedCount, 0);

    await tasks.toggleRecurringCompletion(taskId, today);
    final completed = await _nextMatchingPlan(
      updates,
      (plan) => plan.completedCount == 1,
    );
    expect(completed.progressPercent, 100);

    await tasks.toggleRecurringCompletion(taskId, today);
    final cancelled = await _nextMatchingPlan(
      updates,
      (plan) => plan.completedCount == 0,
    );
    expect(cancelled.dueCount, 1);
    expect(cancelled.progressPercent, 0);
  });

  test('an existing plan subscription follows a linked task schedule edit',
      () async {
    final today = dateOnly(DateTime.now());
    final taskId = await tasks.saveRecurringTask(
      RecurringTaskDraft(
        name: '每日阅读',
        colorValue: 1,
        executionMode: RecurringExecutionMode.untimed,
        schedulePreset: SchedulePreset.daily,
        weekdays: WeekdayMask.toDays(WeekdayMask.everyDay),
        startsOn: today,
        holidayPause: false,
      ),
    );
    await plans.save(
      PlanDraft(
        name: '今天的阅读',
        type: PlanType.month,
        colorValue: 1,
        startsOn: today,
        endsOn: today,
        taskIds: {taskId},
      ),
    );
    final updates = StreamIterator(plans.watchPlans());
    addTearDown(updates.cancel);
    expect((await _nextMatchingPlan(updates, (_) => true)).dueCount, 1);

    await tasks.saveRecurringTask(
      RecurringTaskDraft(
        name: '改为明天阅读',
        colorValue: 1,
        executionMode: RecurringExecutionMode.untimed,
        schedulePreset: SchedulePreset.custom,
        weekdays: {today.weekday % 7 + 1},
        startsOn: today,
        holidayPause: false,
      ),
      taskId: taskId,
    );
    final updated = await _nextMatchingPlan(
      updates,
      (plan) => plan.dueCount == 0,
    );
    expect(updated.completedCount, 0);
    expect(updated.taskIds, {taskId});
  });
}
