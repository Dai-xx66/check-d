import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/reviews/data/review_repository.dart';
import 'package:check_d/features/reviews/domain/review_models.dart';
import 'package:check_d/features/tasks/data/task_repository.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late TaskRepository tasks;
  late ReviewRepository reviews;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    final queue = SyncQueueService(database);
    tasks = TaskRepository(database: database, syncQueue: queue, userId: 'u1');
    reviews = ReviewRepository(
      database: database,
      syncQueue: queue,
      userId: 'u1',
    );
  });

  tearDown(() => database.close());

  test('review period uses value equality for provider family caching', () {
    final today = dateOnly(DateTime.now());
    final first = ReviewPeriod(
      type: ReviewType.day,
      startsOn: today,
      endsOn: today,
    );
    final second = ReviewPeriod(
      type: ReviewType.day,
      startsOn: today,
      endsOn: today,
    );

    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });

  test('review snapshot combines completed tasks and timed sessions', () async {
    final today = dateOnly(DateTime.now());
    final taskId = await tasks.saveRecurringTask(
      RecurringTaskDraft(
        name: '阅读',
        colorValue: 0xFF3D73E8,
        executionMode: RecurringExecutionMode.timed,
        schedulePreset: SchedulePreset.daily,
        weekdays: WeekdayMask.toDays(WeekdayMask.everyDay),
        startsOn: today,
        holidayPause: false,
      ),
    );
    await tasks.startTimer(
      taskId,
      now: DateTime(today.year, today.month, today.day, 9),
    );
    await tasks.endTimer(
      taskId,
      now: DateTime(today.year, today.month, today.day, 9, 15),
    );
    await tasks.toggleRecurringCompletion(taskId, today);

    final period = ReviewPeriod(
      type: ReviewType.day,
      startsOn: today,
      endsOn: today,
    );
    final snapshot = await reviews.loadSnapshot(period);
    expect(snapshot.dueCount, 1);
    expect(snapshot.completedCount, 1);
    expect(snapshot.timedSeconds, 900);
  });

  test(
    'one review per period is updated while preserving its identity',
    () async {
      final today = dateOnly(DateTime.now());
      final period = ReviewPeriod(
        type: ReviewType.day,
        startsOn: today,
        endsOn: today,
      );
      const snapshot = ReviewSnapshot(
        dueCount: 2,
        completedCount: 1,
        timedSeconds: 600,
      );
      await reviews.save(
        ReviewDraft(
          period: period,
          snapshot: snapshot,
          happenedText: '整理了资料',
          mood: 4,
        ),
      );
      final first = await reviews.watchReview(period).first;
      await reviews.save(
        ReviewDraft(
          period: period,
          snapshot: snapshot,
          learnedText: '先做重要的事',
          mood: 5,
        ),
      );
      final second = await reviews.watchReview(period).first;

      expect(first!.id, second!.id);
      expect(second.happenedText, isNull);
      expect(second.learnedText, '先做重要的事');
      expect(second.mood, 5);
      expect(second.snapshot.timedSeconds, 600);
    },
  );
}
