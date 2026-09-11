import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/notifications/notification_service.dart';
import 'package:check_d/core/notifications/reminder_scheduler.dart';
import 'package:check_d/core/sync/sync_apply_scope.dart';
import 'package:check_d/core/sync/sync_download_service.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/courses/data/course_repository.dart';
import 'package:check_d/features/courses/data/semester_repository.dart';
import 'package:check_d/features/schedule/data/day_schedule_repository.dart';
import 'package:check_d/features/tasks/data/task_repository.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const userId = 'user-1';
  late AppDatabase database;
  late _FakeRemoteReader remote;
  late SyncDownloadExecutor executor;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    remote = _FakeRemoteReader();
    executor = SyncDownloadExecutor(
      database: database,
      remote: remote,
      applyScope: SyncApplyScope(),
      currentUserId: () => userId,
    );
  });

  tearDown(() => database.close());

  test(
    'empty device restores parent-child graph without enqueuing uploads',
    () async {
      remote.tables.addAll(_fullSnapshot());

      final result = await executor.reconcile();

      expect(result.succeeded, isTrue);
      expect(result.applied, greaterThan(10));
      expect(await database.select(database.tagRecords).get(), hasLength(1));
      expect(
        await database.select(database.semesterRecords).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.scheduleTemplateSegmentRecords).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.courseScheduleRuleRecords).get(),
        hasLength(1),
      );
      expect(await database.select(database.localTasks).get(), hasLength(2));
      expect(
        await database.select(database.timerSessionRecords).get(),
        hasLength(2),
      );
      expect(
        await database.select(database.adHocTimerIntervalRecords).get(),
        hasLength(1),
      );
      expect(await database.select(database.syncOperations).get(), isEmpty);
    },
  );

  test(
    'newer cloud wins, newer local wins, and equal rows are idempotent',
    () async {
      final localTime = DateTime.utc(2030, 1, 1, 10);
      await database
          .into(database.localTasks)
          .insert(
            LocalTasksCompanion.insert(
              id: 'task-1',
              userId: const Value(userId),
              name: '本地旧版本',
              taskType: 'recurring',
              colorValue: 1,
              createdAt: localTime,
              updatedAt: localTime,
            ),
          );
      remote.tables['tasks'] = [
        _row('task-1', {
          'name': '云端新版本',
          'type': 'long_term',
          'color': 2,
          'updated_at': _time(11),
        }),
      ];

      expect((await executor.reconcile()).applied, 1);
      expect((await taskFor(database, 'task-1')).name, '云端新版本');

      await (database.update(
        database.localTasks,
      )..where((r) => r.id.equals('task-1'))).write(
        LocalTasksCompanion(
          name: const Value('本地更新'),
          updatedAt: Value(DateTime.utc(2030, 1, 1, 12)),
        ),
      );
      remote.tables['tasks'] = [
        _row('task-1', {
          'name': '过期云端版本',
          'type': 'long_term',
          'color': 3,
          'updated_at': _time(11),
        }),
      ];

      expect((await executor.reconcile()).skipped, 1);
      expect((await taskFor(database, 'task-1')).name, '本地更新');

      remote.tables['tasks'] = [
        _row('task-1', {
          'name': '相同时间版本',
          'type': 'long_term',
          'color': 4,
          'updated_at': _time(12),
        }),
      ];
      expect((await executor.reconcile()).skipped, 1);
      expect((await taskFor(database, 'task-1')).name, '本地更新');
    },
  );

  test(
    'remote soft delete archives a task and never creates an upload',
    () async {
      final now = DateTime.utc(2030, 1, 1, 10);
      await database
          .into(database.localTasks)
          .insert(
            LocalTasksCompanion.insert(
              id: 'task-delete',
              userId: const Value(userId),
              name: '待删除',
              taskType: 'recurring',
              colorValue: 1,
              createdAt: now,
              updatedAt: now,
            ),
          );
      remote.tables['tasks'] = [
        _row('task-delete', {
          'name': '待删除',
          'type': 'long_term',
          'color': 1,
          'updated_at': _time(11),
          'deleted_at': _time(11),
        }),
      ];

      expect((await executor.reconcile()).applied, 1);
      final restored = await taskFor(database, 'task-delete');
      expect(restored.status, 'archived');
      expect(restored.deletedAt, isNotNull);
      expect(await database.select(database.syncOperations).get(), isEmpty);
    },
  );

  test('failed snapshot fetch applies nothing and is retryable', () async {
    remote.tables['tags'] = [
      _row('tag-1', {'name': '标签', 'color': 1, 'archived': false}),
    ];
    remote.failTable = 'tasks';

    final failed = await executor.reconcile();

    expect(failed.error, isNotNull);
    expect(await database.select(database.tagRecords).get(), isEmpty);
    remote.failTable = null;
    expect((await executor.reconcile()).succeeded, isTrue);
    expect(await database.select(database.tagRecords).get(), hasLength(1));
  });

  test(
    'cross-user rows are ignored and invalid duplicate unfinished timers fail safely',
    () async {
      remote.tables['tags'] = [
        _row('other-tag', {
          'user_id': 'other-user',
          'name': '不属于当前用户',
          'color': 1,
          'archived': false,
        }),
      ];
      expect((await executor.reconcile()).skipped, 1);
      expect(await database.select(database.tagRecords).get(), isEmpty);

      remote.tables.addAll(_fullSnapshot());
      remote.tables['timer_sessions'] = [
        _timer('timer-1', 'task-1'),
        _timer('timer-2', 'task-1'),
      ];
      final invalid = await executor.reconcile();
      expect(invalid.error, isA<SyncRestoreSnapshotException>());
      expect(await database.select(database.localTasks).get(), isEmpty);
    },
  );

  test(
    'multiple timers for different tasks restore and future reminders use the existing scheduler',
    () async {
      remote.tables.addAll(_fullSnapshot());
      final restored = await executor.reconcile();
      expect(restored.succeeded, isTrue);
      expect(
        await database.select(database.timerSessionRecords).get(),
        hasLength(2),
      );

      final notifications = _FakeNotifications();
      final queue = SyncQueueService(database);
      final scheduler = ReminderScheduler(
        notifications: notifications,
        tasks: TaskRepository(
          database: database,
          syncQueue: queue,
          userId: userId,
        ),
        courses: CourseRepository(
          database: database,
          syncQueue: queue,
          userId: userId,
        ),
        semesters: SemesterRepository(
          database: database,
          syncQueue: queue,
          userId: userId,
        ),
        schedule: DayScheduleRepository(
          database: database,
          syncQueue: queue,
          userId: userId,
        ),
      );

      await scheduler.refreshFuture(now: DateTime(2030, 1, 1, 8));

      expect(notifications.cancelledAll, isTrue);
      expect(notifications.scheduled, hasLength(1));
      expect(notifications.scheduled.single.when, DateTime(2030, 1, 1, 10));
    },
  );
}

Future<LocalTask> taskFor(AppDatabase database, String id) => (database.select(
  database.localTasks,
)..where((row) => row.id.equals(id) & row.userId.equals('user-1'))).getSingle();

Map<String, List<Map<String, Object?>>> _fullSnapshot() => {
  'tags': [
    _row('tag-1', {'name': '学习', 'color': 0xFFFF6B9A, 'archived': false}),
  ],
  'schedule_templates': [
    _row('template-1', {
      'name': '默认作息',
      'timezone': 'Asia/Shanghai',
      'is_default': true,
    }),
  ],
  'semesters': [
    _row('semester-1', {
      'name': '2030春',
      'first_week_start_date': '2030-01-01',
      'total_weeks': 20,
      'schedule_template_id': 'template-1',
      'is_current': true,
    }),
  ],
  'schedule_template_segments': [
    _row('segment-1', {
      'template_id': 'template-1',
      'name': '第一节',
      'starts_at_minute': 600,
      'ends_at_minute': 660,
      'segment_type': 'classTime',
      'sort_order': 1,
    }),
  ],
  'courses': [
    _row('course-1', {
      'name': '高等数学',
      'color': 1,
      'semester_id': 'semester-1',
      'status': 'active',
    }),
  ],
  'tasks': [
    _row('task-1', {
      'name': '听力',
      'type': 'long_term',
      'color': 2,
      'tag_id': 'tag-1',
      'status': 'active',
      'icon_name': 'target',
    }),
    _row('task-2', {
      'name': '阅读',
      'type': 'one_time',
      'color': 3,
      'status': 'active',
      'icon_name': 'event',
    }),
  ],
  'long_term_tasks': [
    _row('long-term-row', {
      'task_id': 'task-1',
      'check_mode': 'timer',
      'target_duration_seconds': 1500,
      'holiday_pause': false,
      'scheduled_minute_of_day': 600,
    }),
  ],
  'task_schedules': [
    _row('schedule-1', {
      'task_id': 'task-1',
      'schedule_type': 'daily',
      'weekdays': [1, 2, 3, 4, 5, 6, 7],
      'weekdays_mask': 127,
      'starts_on': '2030-01-01',
      'ends_on': '2030-01-01',
    }),
  ],
  'one_time_reminders': [
    _row('one-time-row', {
      'task_id': 'task-2',
      'scheduled_at': '2030-01-02T10:00:00Z',
      'has_scheduled_date': true,
      'is_timed': false,
    }),
  ],
  'course_schedule_rules': [
    _row('rule-1', {
      'course_id': 'course-1',
      'weekday': 2,
      'week_rule_type': 'everyWeek',
      'week_numbers': [],
      'schedule_template_id': 'template-1',
      'section_ids': ['segment-1'],
      'time_mode': 'periods',
      'starts_at_minute': 600,
      'ends_at_minute': 660,
    }),
  ],
  'daily_item_overrides': [
    _row('override-1', {
      'item_type': 'course',
      'item_id': 'rule-1',
      'local_date': '2030-01-02',
      'action': 'courseChange',
    }),
  ],
  'task_completions': [
    _row('completion-1', {
      'task_id': 'task-1',
      'local_date': '2030-01-01',
      'actual_duration_seconds': 60,
      'progress_percent': 4,
      'target_reached': false,
      'is_success': false,
    }),
  ],
  'timer_sessions': [_timer('timer-1', 'task-1'), _timer('timer-2', 'task-2')],
  'ad_hoc_timers': [
    _row('adhoc-1', {
      'title': '自由专注',
      'color': 4,
      'started_at': '2030-01-01T08:00:00Z',
      'timer_status': 'paused',
      'accumulated_duration_seconds': 120,
    }),
  ],
  'ad_hoc_timer_intervals': [
    _row('interval-1', {
      'timer_id': 'adhoc-1',
      'started_at': '2030-01-01T08:00:00Z',
      'ended_at': '2030-01-01T08:02:00Z',
      'duration_seconds': 120,
    }),
  ],
  'reminder_rules': [
    _row('reminder-1', {
      'owner_type': 'recurring',
      'owner_id': 'task-1',
      'reminder_kind': 'due',
      'enabled': true,
      'timezone': 'Asia/Shanghai',
    }),
  ],
  'alarm_rules': [
    _row('alarm-1', {
      'owner_type': 'recurring',
      'owner_id': 'task-1',
      'enabled': false,
      'behavior': 'once',
    }),
  ],
  'plans': [
    _row('plan-1', {
      'name': '一月计划',
      'type': 'month',
      'color': 5,
      'starts_on': '2030-01-01',
      'ends_on': '2030-01-31',
    }),
  ],
  'plan_tasks': [
    _row('plan-task-row', {
      'plan_id': 'plan-1',
      'task_id': 'task-1',
      'weight': 1,
    }),
  ],
  'reviews': [
    _row('review-1', {
      'type': 'day',
      'period_start': '2030-01-01',
      'period_end': '2030-01-01',
      'objective_snapshot': {},
    }),
  ],
  'tag_revisions': [
    _row('tag-revision-1', {
      'tag_id': 'tag-1',
      'snapshot_json': {},
      'changed_at': _time(10),
    }),
  ],
  'user_preferences': [
    _row('preference-1', {
      'preference_key': 'reminder_defaults',
      'value': {'atTimeEnabled': true},
    }),
  ],
};

Map<String, Object?> _timer(String id, String taskId) => _row(id, {
  'task_id': taskId,
  'started_at': '2030-01-01T08:00:00Z',
  'logical_date': '2030-01-01',
  'duration_seconds': 0,
  'state': 'running',
});

Map<String, Object?> _row(String id, Map<String, Object?> values) => {
  'id': id,
  'user_id': 'user-1',
  'created_at': _time(9),
  'updated_at': _time(10),
  ...values,
};

String _time(int hour) =>
    '2030-01-01T${hour.toString().padLeft(2, '0')}:00:00Z';

class _FakeRemoteReader implements SyncRemoteReader {
  final Map<String, List<Map<String, Object?>>> tables = {};
  String? failTable;

  @override
  Future<List<Map<String, Object?>>> readTable(
    String table, {
    required String userId,
  }) async {
    if (table == failTable) throw StateError('network unavailable');
    return tables[table] ?? const [];
  }
}

class _FakeNotifications implements NotificationPlatformService {
  final scheduled = <_ScheduledNotification>[];
  bool cancelledAll = false;

  @override
  Future<void> cancelAllPending() async {
    cancelledAll = true;
    scheduled.clear();
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<NotificationPermissionState> permissionState() async =>
      NotificationPermissionState.granted;

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<void> scheduleAt({
    required int id,
    required DateTime when,
    required String title,
    required String body,
  }) async {
    scheduled.add(_ScheduledNotification(when));
  }
}

class _ScheduledNotification {
  const _ScheduledNotification(this.when);
  final DateTime when;
}
