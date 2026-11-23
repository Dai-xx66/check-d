import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/app/app_providers.dart';
import 'package:check_d/features/agent/application/agent_providers.dart';
import 'package:check_d/features/agent/application/agent_reminder_providers.dart';
import 'package:check_d/features/agent/data/agent_reminder_store.dart';
import 'package:check_d/features/agent/domain/agent_models.dart';
import 'package:check_d/features/agent/domain/agent_reminder_engine.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  const engine = AgentReminderEngine();
  final start = DateTime.utc(2026, 11, 23, 2); // Beijing 10:00.
  AgentContext context({
    bool enabled = true,
    bool completed = false,
    String owner = 'a',
    List<Object?> feedback = const [],
  }) => AgentContext(
    ownerId: owner,
    revision: 'r',
    data: {
      'profile': {'remindersEnabled': enabled},
      'feedback': feedback,
      'calendarDays': [
        {
          'date': '2026-11-23',
          'events': [
            {
              'id': 'segment-1',
              'entityId': 'task-1',
              'managed': true,
              'type': 'task',
              'title': '听力训练',
              'startMinute': 600,
              'endMinute': 630,
              'completed': completed,
            },
            {
              'id': 'course',
              'managed': true,
              'type': 'course',
              'startMinute': 650,
              'endMinute': 700,
            },
          ],
        },
      ],
    },
  );

  test('start window lasts five minutes and never catches up after it', () {
    final reminders = engine.build(context(), now: start);
    final reminder = reminders.firstWhere(
      (r) => r.kind == AgentReminderKind.start,
    );
    expect(reminder.when, start);
    expect(reminder.isDue(start.subtract(const Duration(seconds: 1))), isFalse);
    expect(reminder.isDue(start.add(const Duration(minutes: 5))), isTrue);
    expect(
      reminder.isDue(start.add(const Duration(minutes: 5, seconds: 1))),
      isFalse,
    );
    expect(reminders.where((r) => r.key.contains('course')), isEmpty);
  });
  test(
    'follow-up begins ten minutes after planned end; a self report suppresses it',
    () {
      final reminder = engine
          .build(context(), now: start)
          .firstWhere((r) => r.kind == AgentReminderKind.followUp);
      expect(reminder.when, start.add(const Duration(minutes: 40)));
      final withFeedback = context(
        feedback: [
          {'taskId': 'task-1', 'date': '2026-11-23', 'source': 'self_reported'},
        ],
      );
      expect(
        engine
            .build(withFeedback, now: start)
            .where((r) => r.kind == AgentReminderKind.followUp),
        isEmpty,
      );
    },
  );
  test(
    'disabled reminders and completed tasks produce no learning prompts',
    () {
      expect(engine.build(context(enabled: false), now: start), isEmpty);
      expect(
        engine
            .build(context(completed: true), now: start)
            .where((r) => r.kind != AgentReminderKind.weeklyReview),
        isEmpty,
      );
    },
  );
  test('weekly prompt is only due Sunday 20:30 through 21:00 Beijing', () {
    final sunday = DateTime.utc(2026, 11, 29, 12, 30);
    final reminder = engine
        .build(context(), now: sunday)
        .firstWhere((r) => r.kind == AgentReminderKind.weeklyReview);
    expect(reminder.when, sunday);
    expect(reminder.isDue(sunday.add(const Duration(minutes: 30))), isTrue);
    expect(
      reminder.isDue(sunday.add(const Duration(minutes: 30, seconds: 1))),
      isFalse,
    );
  });
  test(
    'identity is stable on rebuild and scoped to owner, date and segment',
    () {
      final a = engine.build(context(), now: start).first;
      final again = engine.build(context(), now: start).first;
      final b = engine.build(context(owner: 'b'), now: start).first;
      expect(a.key, again.key);
      expect(a.notificationId, again.notificationId);
      expect(a.notificationId, isNot(b.notificationId));
    },
  );
  test(
    'display dedup survives app restart without creating completion facts',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      expect(
        await AgentReminderStore(
          database,
        ).claimDisplayed('a', 'day:segment:start', () => true),
        isTrue,
      );
      expect(
        await AgentReminderStore(
          database,
        ).claimDisplayed('a', 'day:segment:start', () => true),
        isFalse,
      );
      expect(
        await AgentReminderStore(
          database,
        ).claimDisplayed('b', 'day:segment:start', () => true),
        isTrue,
      );
      expect(
        await AgentReminderStore(
          database,
        ).claimDisplayed('a', 'other', () => false),
        isFalse,
      );
      expect(
        await database.select(database.taskCompletionRecords).get(),
        isEmpty,
      );
      expect(
        await database.select(database.timerSessionRecords).get(),
        isEmpty,
      );
    },
  );

  test(
    'resuming late skips expired start and keeps delivery separate from completion',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          agentOwnerProvider.overrideWithValue('a'),
          agentOwnerGuardProvider.overrideWithValue((_) => true),
          agentRemindersAllowedProvider.overrideWithValue(true),
          agentReminderContextProvider.overrideWith((_) async => context()),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });
      final controller = container.read(
        agentForegroundReminderProvider.notifier,
      );
      await controller.checkNow(now: start.add(const Duration(minutes: 6)));
      expect(container.read(agentForegroundReminderProvider), isNull);
      await controller.checkNow(now: start.add(const Duration(minutes: 40)));
      expect(
        container.read(agentForegroundReminderProvider)?.kind,
        AgentReminderKind.followUp,
      );
      controller.dismiss();
      await controller.checkNow(now: start.add(const Duration(minutes: 41)));
      expect(container.read(agentForegroundReminderProvider), isNull);
      expect(
        await database.select(database.taskCompletionRecords).get(),
        isEmpty,
      );
      expect(
        await database.select(database.timerSessionRecords).get(),
        isEmpty,
      );
    },
  );

  test(
    'short segments expire at their end and delayed body reports remaining time',
    () {
      final source = context();
      final short = AgentContext(
        ownerId: 'a',
        revision: 'r',
        data: {
          ...source.data,
          'taskLinks': [
            {'taskId': 'task-1', 'standard': '听一段并核对答案'},
          ],
          'calendarDays': [
            {
              'date': '2026-11-23',
              'events': [
                {
                  'id': 'short',
                  'entityId': 'task-1',
                  'managed': true,
                  'type': 'task',
                  'title': '听力训练',
                  'startMinute': 600,
                  'endMinute': 603,
                },
              ],
            },
          ],
        },
      );
      final reminder = engine
          .build(short, now: start.add(const Duration(minutes: 2)))
          .firstWhere((r) => r.kind == AgentReminderKind.start);
      expect(reminder.body, contains('实际剩余1分钟'));
      expect(reminder.body, contains('10:02—10:03'));
      expect(reminder.body, contains('听一段并核对答案'));
      expect(reminder.body.length, lessThanOrEqualTo(180));
      expect(reminder.isDue(start.add(const Duration(minutes: 3))), isFalse);
      expect(reminder.isDue(start.add(const Duration(minutes: 4))), isFalse);
    },
  );
  test(
    'only the final segment asks for daily feedback and last Sunday collects next month',
    () {
      final source = context();
      final multi = AgentContext(
        ownerId: 'a',
        revision: 'r',
        data: {
          ...source.data,
          'goals': [
            {'name': '英语', 'startsOn': '2026-08-29'},
          ],
          'calendarDays': [
            {
              'date': '2026-11-23',
              'events': [
                {
                  'id': 'first',
                  'managed': true,
                  'type': 'task',
                  'startMinute': 600,
                  'endMinute': 630,
                },
                {
                  'id': 'last',
                  'managed': true,
                  'type': 'task',
                  'startMinute': 720,
                  'endMinute': 750,
                },
              ],
            },
          ],
        },
      );
      final reminders = engine.build(multi, now: start);
      expect(
        reminders.where((r) => r.kind == AgentReminderKind.followUp),
        hasLength(1),
      );
      expect(
        reminders.firstWhere((r) => r.key.endsWith('first:start')).body,
        isNot(contains('结束后可回复')),
      );
      final weekly = reminders.firstWhere(
        (r) => r.kind == AgentReminderKind.weeklyReview,
      );
      expect(weekly.body, contains('下月课表'));
      expect(weekly.request, contains('简短收集模板'));
      expect(weekly.request, contains('三个月阶段复核'));
      expect(
        engine
            .build(context(), now: start)
            .firstWhere((r) => r.kind == AgentReminderKind.weeklyReview)
            .body,
        isNot(contains('三个月阶段复核')),
      );
    },
  );
}
