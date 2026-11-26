import 'dart:convert';

import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/agent/data/agent_repository.dart';
import 'package:check_d/features/agent/domain/agent_models.dart';
import 'package:check_d/features/courses/data/course_repository.dart';
import 'package:check_d/features/courses/domain/course_models.dart';
import 'package:check_d/features/schedule/data/day_schedule_repository.dart';
import 'package:check_d/features/schedule/domain/day_schedule_models.dart';
import 'package:check_d/features/tasks/data/task_repository.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late AgentRepository agent;
  late TaskRepository tasks;
  var sequence = 0;
  final now = DateTime(2026, 11, 23, 8);

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    agent = AgentRepository(
      database: database,
      userId: 'owner-a',
      clock: () => now,
    );
    tasks = TaskRepository(
      database: database,
      syncQueue: SyncQueueService(database),
      userId: 'owner-a',
    );
    await agent.saveProfile({
      'confirmedFrom': '2026-11-23',
      'confirmedThrough': '2026-11-29',
    });
  });
  tearDown(() => database.close());

  Future<AgentProposal> proposal(List<AgentOperation> operations) async =>
      AgentProposal(
        id: 'proposal-${sequence++}',
        reply: '调整预览',
        contextRevision: (await agent.buildContext()).revision,
        operations: operations,
      );

  test(
    'profile guards sleep and automatic apply, and feedback validates source and minutes',
    () async {
      expect((await agent.loadWorkspace()).profile['autoApply'], isFalse);
      await expectLater(
        agent.saveProfile({'sleepStartMinute': 0, 'sleepEndMinute': 0}),
        throwsA(isA<AgentException>()),
      );
      await expectLater(
        agent.saveProfile({'autoApply': 'yes'}),
        throwsA(isA<AgentException>()),
      );
      for (final invalid in [-1, 1441, 1.5, double.nan, '20']) {
        await expectLater(
          agent.applyProposal(
            await proposal([
              AgentOperation(
                action: 'record_feedback',
                data: {'actualMinutes': invalid},
              ),
            ]),
          ),
          throwsA(isA<AgentException>()),
        );
      }
      await expectLater(
        agent.applyProposal(
          await proposal([
            const AgentOperation(
              action: 'record_feedback',
              data: {'source': 'verified'},
            ),
          ]),
        ),
        throwsA(isA<AgentException>()),
      );
      await agent.applyProposal(
        await proposal([
          const AgentOperation(
            action: 'record_feedback',
            data: {
              'source': 'artifact',
              'actualMinutes': 20,
              'evidence': 'Uploaded worksheet',
            },
          ),
        ]),
      );
      final feedback = (await agent.loadWorkspace()).feedback.single;
      expect(feedback['source'], 'artifact');
      expect(feedback['verification'], 'unverified');
      expect(feedback['isExecutionFact'], isFalse);
      expect(
        await database.select(database.timerSessionRecords).get(),
        isEmpty,
      );
    },
  );

  test(
    'busy period can be recorded before availability is confirmed without reflow',
    () async {
      await agent.saveProfile({'confirmedFrom': '', 'confirmedThrough': ''});
      final draft = await proposal([
        const AgentOperation(
          action: 'add_busy_period',
          data: {
            'date': '2026-11-24',
            'startMinute': 600,
            'durationMinutes': 45,
          },
        ),
      ]);
      final preview = await agent.prepareProposal(draft);
      expect(preview.operations, hasLength(1));
      expect(preview.warnings, isNotEmpty);
      await agent.applyProposal(preview);
      expect(
        (await agent.loadWorkspace()).busyPeriods.single['durationMinutes'],
        45,
      );
      expect(await database.select(database.localTasks).get(), isEmpty);
    },
  );

  test('agent rescheduling preserves existing manual reminder rules', () async {
    final id = await tasks.saveOneTimeReminder(
      OneTimeReminderDraft(
        name: 'Manual',
        colorValue: 1,
        scheduledAt: DateTime(2026, 11, 23, 18),
      ),
    );
    final schedule = DayScheduleRepository(
      database: database,
      syncQueue: SyncQueueService(database),
      userId: 'owner-a',
    );
    await schedule.saveDailyOverride(
      DailyItemOverrideDraft(
        itemType: DayItemType.oneTime,
        itemId: id,
        localDate: DateTime(2026, 11, 23),
        action: DayOverrideAction.reschedule,
        plannedStartMinute: 1080,
        plannedEndMinute: 1110,
      ),
    );
    final reminderId = await schedule.saveReminderRule(
      ReminderRuleDraft(
        ownerType: DayItemType.oneTime,
        ownerId: id,
        reminderKind: ReminderKind.advance,
        remindBeforeMinutes: 15,
      ),
    );
    final before =
        (await database.select(database.reminderRuleRecords).get()).single;
    await agent.applyProposal(
      await proposal([
        AgentOperation(
          action: 'reschedule_task',
          entityId: id,
          data: const {
            'date': '2026-11-23',
            'startMinute': 1140,
            'endMinute': 1170,
          },
        ),
      ]),
    );
    final after =
        (await database.select(database.reminderRuleRecords).get()).single;
    expect(after.id, reminderId);
    expect(after.enabled, before.enabled);
    expect(after.remindBeforeMinutes, 15);
    expect(after.deletedAt, isNull);
  });

  test(
    'cloud context is bounded while revision and execution totals include omitted history',
    () async {
      final id = await tasks.saveOneTimeReminder(
        const OneTimeReminderDraft(name: 'Active', colorValue: 1),
      );
      await database.batch((batch) {
        batch.insertAll(
          database.localTasks,
          List.generate(
            100,
            (i) => LocalTasksCompanion.insert(
              id: 'archived-$i',
              userId: const Value('owner-a'),
              name: 'Private archived $i',
              taskType: 'oneTime',
              colorValue: 1,
              status: const Value('archived'),
              notes: Value(List.filled(4000, 'x').join()),
              createdAt: now.toUtc(),
              updatedAt: now.toUtc(),
            ),
          ),
        );
        batch.insertAll(
          database.timerSessionRecords,
          List.generate(120, (i) {
            final start = now.subtract(Duration(days: i, hours: 1)).toUtc();
            return TimerSessionRecordsCompanion.insert(
              id: 'fact-$i',
              taskId: id,
              userId: 'owner-a',
              startedAt: start,
              endedAt: Value(start.add(const Duration(minutes: 1))),
              durationSeconds: const Value(60),
              state: 'finished',
              createdAt: start,
              updatedAt: start,
            );
          }),
        );
      });
      final context = await agent.buildContext();
      expect(jsonEncode(context.data).length, greaterThan(240000));
      final sent = context.toJson();
      expect(jsonEncode(sent).length, lessThan(180000));
      expect((sent['timerSessions'] as List), hasLength(40));
      expect((sent['executionTotals'] as Map)['timerSessionCount'], 120);
      expect((sent['executionTotals'] as Map)['allTimeFocusSeconds'], 7200);
      expect(
        (sent['contextCoverage'] as Map)['records']['timerSessions']['omitted'],
        80,
      );
      expect(jsonEncode(sent), isNot(contains('Private archived')));
      await database.customUpdate(
        "UPDATE local_tasks SET name = 'Changed omitted row' WHERE id = 'archived-0' AND user_id = 'owner-a'",
      );
      expect((await agent.buildContext()).revision, isNot(context.revision));
    },
  );

  AgentOperation createTask({
    String? id,
    String name = 'Reading',
    bool recurring = false,
  }) => AgentOperation(
    action: 'create_task',
    entityId: id,
    data: {
      'name': name,
      'kind': recurring ? 'recurring' : 'oneTime',
      'executionMode': 'timed',
      'durationMinutes': 30,
      'standard': '记录笔记后手动完成',
      if (recurring) ...{
        'startsOn': '2026-11-23',
        'endsOn': '2026-11-29',
        'weekdays': [1, 2, 3, 4, 5, 6, 7],
        'schedulePreset': 'daily',
        'targetDurationSeconds': 1800,
      },
    },
  );

  test(
    'workspace and chat are isolated and messages do not invalidate proposal context',
    () async {
      final revision = (await agent.buildContext()).revision;
      await agent.appendMessage(
        AgentChatMessage(role: 'user', text: '请帮助安排时间', createdAt: now),
      );
      expect((await agent.buildContext()).revision, revision);
      final other = AgentRepository(
        database: database,
        userId: 'owner-b',
        clock: () => now,
      );
      expect((await other.loadWorkspace()).messages, isEmpty);
      expect((await other.buildContext()).revision, isNot(revision));
      await agent.clearConversation();
      expect((await agent.loadWorkspace()).messages, isEmpty);
      expect((await agent.loadWorkspace()).profile['learningShare'], .2);
    },
  );

  test('preview and abandoned proposal do not mutate tasks or queue', () async {
    final draft = await proposal([createTask()]);
    await agent.prepareProposal(draft);
    expect(await database.select(database.localTasks).get(), isEmpty);
    expect(await database.select(database.syncOperations).get(), isEmpty);
    expect((await agent.loadWorkspace()).history, isEmpty);
  });

  test(
    'confirmed learning block writes one task and slot without duplicate reminder rules',
    () async {
      await agent.saveProfile({'remindersEnabled': true});
      final draft = await proposal([
        const AgentOperation(
          action: 'create_task',
          data: {
            'name': 'Reading practice',
            'kind': 'oneTime',
            'executionMode': 'timed',
            'scheduledAt': '2026-11-23T18:00:00',
            'durationMinutes': 30,
          },
        ),
      ]);
      expect((await agent.applyProposal(draft)).changedCount, greaterThan(0));
      final task = (await database.select(database.localTasks).get()).single;
      final slot =
          (await database.select(database.dailyItemOverrideRecords).get())
              .single;
      expect(slot.itemId, task.id);
      expect(slot.plannedEndMinute! - slot.plannedStartMinute!, 30);
      final rules = await database.select(database.reminderRuleRecords).get();
      expect(rules, isEmpty);
      expect(
        await database.select(database.timerSessionRecords).get(),
        isEmpty,
      );
      expect(
        await database.select(database.taskCompletionRecords).get(),
        isEmpty,
      );
      expect((await agent.applyProposal(draft)).alreadyApplied, isTrue);
      expect(await database.select(database.localTasks).get(), hasLength(1));
      expect((await agent.loadWorkspace()).history, hasLength(1));
    },
  );

  test(
    'any invalid later operation rolls back all earlier records and outbox',
    () async {
      final draft = await proposal([
        createTask(),
        const AgentOperation(
          action: 'update_task',
          entityId: 'not-owned',
          data: {'name': 'No access'},
        ),
      ]);
      await expectLater(
        agent.applyProposal(draft),
        throwsA(isA<AgentException>()),
      );
      expect(await database.select(database.localTasks).get(), isEmpty);
      expect(await database.select(database.syncOperations).get(), isEmpty);
      expect((await agent.loadWorkspace()).history, isEmpty);
    },
  );

  test(
    'stale context and cross-account identities are rejected without mutation',
    () async {
      final draft = await proposal([createTask()]);
      await agent.saveProfile({'livingMinutesPerDay': 200});
      await expectLater(
        agent.applyProposal(draft),
        throwsA(
          isA<AgentException>().having((e) => e.code, 'code', 'stale_proposal'),
        ),
      );
      final foreign = TaskRepository(
        database: database,
        syncQueue: SyncQueueService(database),
        userId: 'owner-b',
      );
      final foreignId = await foreign.saveOneTimeReminder(
        const OneTimeReminderDraft(name: 'Private', colorValue: 1),
      );
      final update = await proposal([
        AgentOperation(
          action: 'update_task',
          entityId: foreignId,
          data: const {'name': 'Stolen'},
        ),
      ]);
      await expectLater(
        agent.applyProposal(update),
        throwsA(isA<AgentException>()),
      );
      expect((await foreign.getTask(foreignId))!.name, 'Private');
      expect(await tasks.getTask(foreignId), isNull);
    },
  );

  test(
    'unresolved questions and fabricated execution facts cannot be applied',
    () async {
      final revision = (await agent.buildContext()).revision;
      await expectLater(
        agent.applyProposal(
          AgentProposal(
            id: 'questions',
            reply: '补充',
            contextRevision: revision,
            operations: [createTask()],
            questions: const ['何时有空？'],
          ),
        ),
        throwsA(isA<AgentException>()),
      );
      await expectLater(
        agent.applyProposal(
          await proposal([
            const AgentOperation(
              action: 'create_task',
              data: {
                'name': 'Fake',
                'kind': 'oneTime',
                'completedAt': '2026-11-23T10:00:00',
              },
            ),
          ]),
        ),
        throwsA(isA<AgentException>()),
      );
      expect(await database.select(database.localTasks).get(), isEmpty);
    },
  );

  test(
    'goals, tags, tasks and plans use existing repositories and support updates',
    () async {
      await agent.applyProposal(
        await proposal([
          const AgentOperation(
            action: 'upsert_goal',
            entityId: 'goal-1',
            data: {'name': 'Read regularly', 'target': 'Build a routine'},
          ),
          const AgentOperation(
            action: 'create_tag',
            entityId: 'tag-new',
            data: {'name': 'Practice', 'colorValue': 2},
          ),
          AgentOperation(
            action: 'create_task',
            entityId: 'task-new',
            data: {
              ...createTask(recurring: true).data,
              'tagId': 'tag-new',
              'goalId': 'goal-1',
            },
          ),
          const AgentOperation(
            action: 'create_plan',
            entityId: 'plan-new',
            data: {
              'name': 'This month',
              'type': 'month',
              'startsOn': '2026-11-23',
              'endsOn': '2026-11-29',
              'taskIds': ['task-new'],
            },
          ),
        ]),
      );
      final task = (await database.select(database.localTasks).get()).single;
      final tag = (await database.select(database.tagRecords).get()).single;
      final plan = (await database.select(database.planRecords).get()).single;
      expect(task.tagId, tag.id);
      expect(
        (await database.select(database.planTaskRecords).get()).single.taskId,
        task.id,
      );
      expect(
        (await agent.loadWorkspace()).taskLinks.single['goalId'],
        'goal-1',
      );
      await agent.applyProposal(
        await proposal([
          AgentOperation(
            action: 'update_task',
            entityId: task.id,
            data: const {'name': 'Updated routine'},
          ),
          AgentOperation(
            action: 'update_tag',
            entityId: tag.id,
            data: const {'name': 'New tag'},
          ),
          AgentOperation(
            action: 'update_plan',
            entityId: plan.id,
            data: const {'name': 'Updated plan'},
          ),
          AgentOperation(
            action: 'record_feedback',
            data: {
              'taskId': task.id,
              'text': 'Reported finishing one practice',
            },
          ),
        ]),
      );
      expect((await tasks.getTask(task.id))!.name, 'Updated routine');
      expect(
        (await database.select(database.tagRecords).get()).single.name,
        'New tag',
      );
      expect(
        (await database.select(database.planRecords).get()).single.name,
        'Updated plan',
      );
      expect(
        (await agent.loadWorkspace()).feedback.single['source'],
        'self_report',
      );
      expect(
        await database.select(database.taskCompletionRecords).get(),
        isEmpty,
      );
      await agent.applyProposal(
        await proposal([
          AgentOperation(action: 'archive_plan', entityId: plan.id),
          AgentOperation(action: 'archive_tag', entityId: tag.id),
          const AgentOperation(action: 'archive_goal', entityId: 'goal-1'),
          AgentOperation(action: 'archive_task', entityId: task.id),
        ]),
      );
      expect((await tasks.getTask(task.id))!.status, TaskLifecycle.archived);
      expect(
        (await database.select(database.planRecords).get()).single.deletedAt,
        isNotNull,
      );
      expect(
        (await database.select(database.tagRecords).get()).single.archived,
        isTrue,
      );
    },
  );

  test('course one-day update leaves recurring rules unchanged', () async {
    await agent.applyProposal(
      await proposal([
        const AgentOperation(
          action: 'create_course',
          data: {
            'name': 'Mathematics',
            'rules': [
              {
                'weekday': 1,
                'weekRuleType': 'everyWeek',
                'startsAtMinute': 540,
                'endsAtMinute': 600,
              },
            ],
          },
        ),
      ]),
    );
    final course = (await database.select(database.courseRecords).get()).single;
    final rule =
        (await database.select(database.courseScheduleRuleRecords).get())
            .single;
    await agent.applyProposal(
      await proposal([
        AgentOperation(
          action: 'update_course_day',
          entityId: course.id,
          data: const {
            'date': '2026-11-23',
            'startMinute': 660,
            'endMinute': 720,
            'temporaryClassroom': 'Room B',
          },
        ),
      ]),
    );
    final unchanged =
        (await database.select(database.courseScheduleRuleRecords).get())
            .single;
    expect(unchanged.startsAtMinute, rule.startsAtMinute);
    expect(unchanged.endsAtMinute, rule.endsAtMinute);
    final exception =
        (await database.select(database.dailyItemOverrideRecords).get()).single;
    expect(exception.itemType, 'course');
    expect(exception.plannedStartMinute, 660);
    await agent.applyProposal(
      await proposal([
        AgentOperation(
          action: 'update_course',
          entityId: course.id,
          data: const {'name': 'New name'},
        ),
      ]),
    );
    expect(
      (await database.select(database.courseRecords).get()).single.name,
      'New name',
    );
    await agent.applyProposal(
      await proposal([
        AgentOperation(action: 'archive_course', entityId: course.id),
      ]),
    );
    expect(
      (await database.select(database.courseRecords).get()).single.deletedAt,
      isNotNull,
    );
  });

  test(
    'busy periods and self-reported feedback are reversible workspace data',
    () async {
      await agent.applyProposal(
        await proposal([
          const AgentOperation(
            action: 'add_busy_period',
            entityId: 'meeting',
            data: {
              'title': 'Event',
              'startsAt': '2026-11-24T12:00:00',
              'endsAt': '2026-11-24T13:00:00',
            },
          ),
          const AgentOperation(
            action: 'record_feedback',
            data: {'text': 'I felt tired'},
          ),
        ]),
      );
      final busy = (await agent.loadWorkspace()).busyPeriods.single;
      await agent.applyProposal(
        await proposal([
          AgentOperation(
            action: 'remove_busy_period',
            entityId: busy['id'] as String,
          ),
        ]),
      );
      expect((await agent.loadWorkspace()).busyPeriods, isEmpty);
      await agent.undoLast();
      expect((await agent.loadWorkspace()).busyPeriods, hasLength(1));
      await agent.undoLast();
      expect((await agent.loadWorkspace()).busyPeriods, isEmpty);
      expect((await agent.loadWorkspace()).feedback, isEmpty);
    },
  );

  test(
    'undo restores an edited task and supports successive safe undos',
    () async {
      final id = await tasks.saveOneTimeReminder(
        const OneTimeReminderDraft(name: 'Original', colorValue: 1),
      );
      await agent.applyProposal(
        await proposal([
          AgentOperation(
            action: 'update_task',
            entityId: id,
            data: const {'name': 'First'},
          ),
        ]),
      );
      await agent.applyProposal(
        await proposal([
          AgentOperation(
            action: 'update_task',
            entityId: id,
            data: const {'name': 'Second'},
          ),
        ]),
      );
      await agent.undoLast();
      expect((await tasks.getTask(id))!.name, 'First');
      await agent.undoLast();
      expect((await tasks.getTask(id))!.name, 'Original');
    },
  );

  test(
    'undo archives created plans but keeps later real timer facts intact',
    () async {
      await agent.applyProposal(await proposal([createTask()]));
      final id = (await database.select(database.localTasks).get()).single.id;
      await tasks.startTimer(id, now: now);
      await tasks.endTimer(id, now: now.add(const Duration(minutes: 5)));
      final facts = await database.select(database.timerSessionRecords).get();
      await agent.undoLast();
      expect((await tasks.getTask(id))!.status, TaskLifecycle.archived);
      final preserved = await database
          .select(database.timerSessionRecords)
          .get();
      expect(preserved.single.id, facts.single.id);
      expect(preserved.single.durationSeconds, 300);
    },
  );

  test('undo refuses to overwrite a later manual edit', () async {
    final id = await tasks.saveOneTimeReminder(
      const OneTimeReminderDraft(name: 'Original', colorValue: 1),
    );
    await agent.applyProposal(
      await proposal([
        AgentOperation(
          action: 'update_task',
          entityId: id,
          data: const {'name': 'Agent edit'},
        ),
      ]),
    );
    await tasks.saveOneTimeReminder(
      const OneTimeReminderDraft(name: 'Manual edit', colorValue: 1),
      taskId: id,
    );
    await expectLater(
      agent.undoLast(),
      throwsA(
        isA<AgentException>().having((e) => e.code, 'code', 'undo_conflict'),
      ),
    );
    expect((await tasks.getTask(id))!.name, 'Manual edit');
  });

  test(
    'busy reflow writes the same task and undo restores its original slot',
    () async {
      await agent.applyProposal(
        await proposal([
          AgentOperation(
            action: 'create_task',
            data: {...createTask().data, 'scheduledAt': '2026-11-23T18:00:00'},
          ),
        ]),
      );
      final before = (await database.select(database.localTasks).get()).single;
      final draft = await proposal([
        const AgentOperation(
          action: 'add_busy_period',
          data: {
            'date': '2026-11-23',
            'startMinute': 1080,
            'durationMinutes': 60,
            'reason': 'Meeting',
          },
        ),
      ]);
      final preview = await agent.prepareProposal(draft);
      expect(
        preview.operations
            .where((op) => op.action == 'reschedule_task')
            .single
            .entityId,
        before.id,
      );
      await agent.applyProposal(preview);
      expect(await database.select(database.localTasks).get(), hasLength(1));
      expect(
        (await tasks.getTask(before.id))!.scheduledAt,
        isNot(DateTime(2026, 11, 23, 18)),
      );
      await agent.undoLast();
      expect(
        (await tasks.getTask(before.id))!.scheduledAt,
        DateTime(2026, 11, 23, 18),
      );
      expect((await agent.loadWorkspace()).busyPeriods, isEmpty);
      final events =
          ((await agent.buildContext()).data['calendarDays'] as List)
                  .first['events']
              as List;
      expect(events.single['startMinute'], 1080);
      expect(events.single['endMinute'], 1110);
    },
  );

  test(
    'renaming an unmanaged task does not invent a duration or calendar override',
    () async {
      final id = await tasks.saveOneTimeReminder(
        OneTimeReminderDraft(
          name: 'Original',
          colorValue: 1,
          scheduledAt: DateTime(2026, 11, 23, 18),
        ),
      );
      await agent.applyProposal(
        await proposal([
          AgentOperation(
            action: 'update_task',
            entityId: id,
            data: const {'name': 'Renamed'},
          ),
        ]),
      );
      expect((await tasks.getTask(id))!.name, 'Renamed');
      expect(
        await database.select(database.dailyItemOverrideRecords).get(),
        isEmpty,
      );
      expect((await agent.loadWorkspace()).taskLinks, isEmpty);
      final firstDay =
          ((await agent.buildContext()).data['calendarDays'] as List).first;
      expect(firstDay['unknownDuration'], isTrue);
    },
  );

  test(
    'review duration uses actual timer intervals and self reports never add time',
    () async {
      final id = await tasks.saveOneTimeReminder(
        const OneTimeReminderDraft(
          name: 'Measured',
          colorValue: 1,
          executionMode: OneTimeExecutionMode.timed,
        ),
      );
      await tasks.startTimer(
        id,
        now: now.subtract(const Duration(minutes: 10)),
      );
      await tasks.endTimer(id, now: now.subtract(const Duration(minutes: 5)));
      await agent.applyProposal(
        await proposal([
          AgentOperation(
            action: 'record_feedback',
            data: {
              'taskId': id,
              'actualMinutes': 180,
              'content': 'Self report',
            },
          ),
          const AgentOperation(
            action: 'save_review',
            data: {
              'type': 'week',
              'startsOn': '2026-11-23',
              'endsOn': '2026-11-29',
              'summary': 'Based on recorded facts',
            },
          ),
        ]),
      );
      final review =
          (await database.select(database.reviewRecords).get()).single;
      expect(jsonDecode(review.objectiveSnapshotJson)['timed_seconds'], 300);
      expect(
        (await database.select(database.timerSessionRecords).get())
            .single
            .durationSeconds,
        300,
      );
      await agent.undoLast();
      expect(
        (await database.select(database.timerSessionRecords).get())
            .single
            .durationSeconds,
        300,
      );
    },
  );

  test(
    'history keeps twenty changes and owner guard prevents stale-account writes',
    () async {
      for (var i = 0; i < 22; i++) {
        await agent.applyProposal(
          await proposal([
            AgentOperation(
              action: 'upsert_goal',
              entityId: 'goal-history',
              data: {'name': 'Goal $i'},
            ),
          ]),
        );
      }
      expect((await agent.loadWorkspace()).history, hasLength(20));
      final guarded = AgentRepository(
        database: database,
        userId: 'owner-a',
        clock: () => now,
        isCurrentOwner: () => false,
      );
      await expectLater(
        guarded.saveProfile({'learningShare': .3}),
        throwsA(
          isA<AgentException>().having(
            (e) => e.code,
            'code',
            'account_changed',
          ),
        ),
      );
      expect((await agent.loadWorkspace()).profile['learningShare'], .2);
    },
  );

  test(
    'context exposes actual courses and timer facts only for the current account',
    () async {
      final courses = CourseRepository(
        database: database,
        syncQueue: SyncQueueService(database),
        userId: 'owner-a',
      );
      final id = await courses.saveCourse(
        const CourseDraft(name: 'Owned course', colorValue: 1),
      );
      await courses.saveScheduleRule(
        CourseScheduleRuleDraft(
          courseId: id,
          weekday: 1,
          weekRuleType: CourseWeekRuleType.everyWeek,
          startsAtMinute: 540,
          endsAtMinute: 600,
        ),
      );
      final foreign = AgentRepository(
        database: database,
        userId: 'owner-b',
        clock: () => now,
      );
      final context = await agent.buildContext();
      expect((context.data['courses'] as List).single['name'], 'Owned course');
      await expectLater(
        (foreign.buildContext()),
        completion(
          isA<AgentContext>().having(
            (c) => c.data['courses'],
            'courses',
            isEmpty,
          ),
        ),
      );
      final firstDay = (context.data['calendarDays'] as List).first as Map;
      expect((firstDay['events'] as List).single['type'], 'course');
      expect((firstDay['events'] as List).single['startMinute'], 540);
    },
  );
}
