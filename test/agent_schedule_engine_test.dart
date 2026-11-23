import 'package:check_d/features/agent/domain/agent_models.dart';
import 'package:check_d/features/agent/domain/agent_schedule_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 23, 8);
  test('equal sleep boundaries cannot produce a zero-sleep budget', () {
    expect(
      () => AgentScheduleEngine.availableBudgetMinutes(
        calendarDays: const [],
        profile: const {'sleepStartMinute': 0, 'sleepEndMinute': 0},
      ),
      throwsA(isA<AgentException>()),
    );
  });
  Map<String, Object?> profile() => {
    'confirmedFrom': '2026-11-23',
    'confirmedThrough': '2026-11-23',
    'learningShare': .2,
    'sleepStartMinute': 0,
    'sleepEndMinute': 450,
    'livingMinutesPerDay': 180,
  };
  Map<String, Object?> day({
    List<Map<String, Object?>> events = const [],
    bool unknown = false,
    String date = '2026-11-23',
  }) => {'date': date, 'events': events, 'unknownDuration': unknown};
  Map<String, Object?> taskSlot({bool completed = false}) => {
    'entityId': 'task-1',
    'id': 'task-occurrence-1',
    'type': 'task',
    'startMinute': 1080,
    'endMinute': 1110,
    'managed': true,
    'completed': completed,
    'title': 'Practice',
  };
  AgentProposal prepare(
    List<AgentOperation> operations, {
    List<Map<String, Object?>>? days,
    List<Map<String, Object?>> courses = const [],
    bool completed = false,
    Map<String, Object?>? userProfile,
    bool pending = false,
  }) {
    final actualProfile = userProfile ?? profile();
    final workspace = AgentWorkspace(
      profile: actualProfile,
      taskLinks: [
        {
          'taskId': 'task-1',
          'durationMinutes': 30,
          'goalId': 'goal-1',
          if (pending) 'needsScheduling': true,
        },
      ],
    );
    final context = AgentContext(
      ownerId: 'user-1',
      revision: 'revision',
      data: {
        'calendarDays':
            days ??
            [
              day(events: [taskSlot(completed: completed)]),
            ],
        'tasks': [
          {
            'id': 'task-1',
            'name': 'Practice',
            'kind': 'oneTime',
            'status': 'active',
            if (completed) 'completedAt': '2026-11-23T18:30:00',
          },
        ],
        'courses': courses,
      },
    );
    return AgentScheduleEngine.prepare(
      context: context,
      workspace: workspace,
      proposal: AgentProposal(
        id: 'test',
        reply: 'preview',
        contextRevision: 'revision',
        operations: operations,
      ),
      now: now,
    );
  }

  test(
    'shared 20 percent budget counts all goals once and excludes unconfirmed days',
    () {
      final days = [day(), day(date: '2026-11-24')];
      final operations = List.generate(
        3,
        (index) => AgentOperation(
          action: 'create_task',
          data: {
            'kind': 'oneTime',
            'name': 'Goal $index',
            'goalId': 'goal-$index',
            'scheduledAt': '2026-11-23T${10 + index * 2}:00:00',
            'durationMinutes': 60,
          },
        ),
      );
      expect(
        () => prepare(operations, days: days),
        throwsA(isA<AgentException>()),
      );
      expect(
        prepare(operations.take(2).toList(), days: days).operations,
        hasLength(2),
      );
      expect(
        AgentScheduleEngine.availableBudgetMinutes(
          calendarDays: days,
          profile: profile(),
        ),
        162,
      );
    },
  );

  test(
    'fixed overlaps are unioned and managed study is not deducted twice',
    () {
      final days = [
        day(
          events: [
            {
              'id': 'course',
              'type': 'course',
              'startMinute': 900,
              'endMinute': 960,
            },
            {
              'id': 'meeting',
              'type': 'busy',
              'startMinute': 930,
              'endMinute': 1020,
            },
            taskSlot(),
          ],
        ),
      ];
      expect(
        AgentScheduleEngine.availableBudgetMinutes(
          calendarDays: days,
          profile: profile(),
        ),
        138,
      );
    },
  );

  test(
    'temporary busy period moves future managed work using the same task identity',
    () {
      final result = prepare([
        const AgentOperation(
          action: 'add_busy_period',
          entityId: 'meeting',
          data: {
            'date': '2026-11-23',
            'startMinute': 1080,
            'durationMinutes': 60,
            'reason': 'New meeting',
          },
        ),
      ]);
      final move = result.operations
          .where((op) => op.action == 'reschedule_task')
          .single;
      expect(move.entityId, 'task-1');
      expect(move.data['unscheduled'], isNot(true));
      expect(move.data['startMinute'], isNot(1080));
      expect(
        result.operations.where((op) => op.action == 'create_task'),
        isEmpty,
      );
    },
  );

  test(
    'completed and already-started work cannot be automatically displaced',
    () {
      final busy = const AgentOperation(
        action: 'add_busy_period',
        data: {
          'date': '2026-11-23',
          'startMinute': 1080,
          'durationMinutes': 60,
        },
      );
      expect(
        () => prepare([busy], completed: true),
        throwsA(isA<AgentException>()),
      );
      final early = taskSlot()
        ..['startMinute'] = 420
        ..['endMinute'] = 540;
      expect(
        () => prepare(
          [
            const AgentOperation(
              action: 'reschedule_task',
              entityId: 'task-1',
              data: {
                'date': '2026-11-23',
                'startMinute': 600,
                'endMinute': 630,
              },
            ),
          ],
          days: [
            day(events: [early]),
          ],
        ),
        throwsA(isA<AgentException>()),
      );
    },
  );

  test('unknown course or task duration blocks precise automatic planning', () {
    final op = const AgentOperation(
      action: 'create_task',
      data: {
        'name': 'New',
        'scheduledAt': '2026-11-23T18:00:00',
        'durationMinutes': 30,
      },
    );
    expect(
      () => prepare([op], days: [day(unknown: true)]),
      throwsA(isA<AgentException>()),
    );
    expect(
      AgentScheduleEngine.availableBudgetMinutes(
        calendarDays: [day(unknown: true)],
        profile: profile(),
      ),
      0,
    );
    expect(
      () => prepare([op], userProfile: const {}),
      throwsA(isA<AgentException>()),
    );
  });

  test('a course day change preserves other courses and other rules', () {
    final events = <Map<String, Object?>>[
      {
        'entityId': 'course-1',
        'ruleId': 'rule-a',
        'type': 'course',
        'startMinute': 540,
        'endMinute': 600,
      },
      {
        'entityId': 'course-1',
        'ruleId': 'rule-b',
        'type': 'course',
        'startMinute': 660,
        'endMinute': 720,
      },
      {
        'entityId': 'course-2',
        'ruleId': 'rule-c',
        'type': 'course',
        'startMinute': 780,
        'endMinute': 840,
      },
    ];
    final valid = prepare(
      [
        const AgentOperation(
          action: 'update_course_day',
          entityId: 'course-1',
          data: {
            'date': '2026-11-23',
            'ruleId': 'rule-a',
            'startMinute': 600,
            'endMinute': 630,
          },
        ),
      ],
      days: [day(events: events)],
    );
    expect(valid.operations, hasLength(1));
    expect(
      () => prepare(
        [
          const AgentOperation(
            action: 'update_course_day',
            entityId: 'course-1',
            data: {
              'date': '2026-11-23',
              'ruleId': 'rule-a',
              'startMinute': 690,
              'endMinute': 750,
            },
          ),
        ],
        days: [day(events: events)],
      ),
      throwsA(isA<AgentException>()),
    );
    expect(
      () => prepare(
        [
          const AgentOperation(
            action: 'update_course_day',
            entityId: 'course-1',
            data: {
              'date': '2026-11-23',
              'ruleId': 'rule-a',
              'startMinute': 800,
              'endMinute': 860,
            },
          ),
        ],
        days: [day(events: events)],
      ),
      throwsA(isA<AgentException>()),
    );
  });

  test('new course rules are projected before existing study is reflowed', () {
    final result = prepare([
      const AgentOperation(
        action: 'create_course',
        entityId: 'new-course',
        data: {
          'name': 'Class',
          'rules': [
            {
              'weekday': 1,
              'startsAtMinute': 1080,
              'endsAtMinute': 1140,
              'weekRuleType': 'everyWeek',
            },
          ],
        },
      ),
    ]);
    final move = result.operations
        .where((op) => op.action == 'reschedule_task')
        .single;
    expect(move.entityId, 'task-1');
    expect(move.data['startMinute'], isNot(1080));
  });

  test('a new course cannot quietly displace an unmanaged personal task', () {
    final slot = taskSlot()..['managed'] = false;
    expect(
      () => prepare(
        [
          const AgentOperation(
            action: 'create_course',
            data: {
              'name': 'Class',
              'rules': [
                {
                  'weekday': 1,
                  'startsAtMinute': 1080,
                  'endsAtMinute': 1140,
                  'weekRuleType': 'everyWeek',
                },
              ],
            },
          ),
        ],
        days: [
          day(events: [slot]),
        ],
      ),
      throwsA(isA<AgentException>()),
    );
  });

  test('unplaceable study is retained as unscheduled rather than deleted', () {
    final result = prepare(
      [
        const AgentOperation(
          action: 'add_busy_period',
          data: {
            'date': '2026-11-23',
            'startMinute': 480,
            'durationMinutes': 480,
          },
        ),
      ],
      userProfile: {...profile(), 'livingMinutesPerDay': 900},
    );
    final move = result.operations
        .where((op) => op.action == 'reschedule_task')
        .single;
    expect(move.entityId, 'task-1');
    expect(move.data['unscheduled'], isTrue);
    expect(
      result.operations.where((op) => op.action == 'archive_task'),
      isEmpty,
    );
  });

  test('reflow can place a previously retained pending item', () {
    final result = prepare(
      [
        const AgentOperation(
          action: 'remove_busy_period',
          entityId: 'old-busy',
        ),
      ],
      days: [day()],
      pending: true,
    );
    final move = result.operations
        .where((op) => op.action == 'reschedule_task')
        .single;
    expect(move.entityId, 'task-1');
    expect(move.data['unscheduled'], isNot(true));
  });
}
