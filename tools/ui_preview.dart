// Local visual review with isolated sample data.
// flutter build web -t tools/ui_preview.dart
import 'package:check_d/app/app.dart';
import 'package:check_d/app/app_providers.dart';
import 'package:check_d/core/config/app_config.dart';
import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/core/theme/app_skin.dart';
import 'package:check_d/core/theme/appearance_preferences.dart';
import 'package:check_d/features/auth/presentation/auth_controller.dart';
import 'package:check_d/features/courses/data/course_repository.dart';
import 'package:check_d/features/courses/domain/course_models.dart';
import 'package:check_d/features/tasks/data/task_repository.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
import 'package:check_d/features/tags/data/tag_repository.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN');
  final database = AppDatabase.forTesting(
    driftDatabase(
      name: 'check_d_visual_review',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    ),
  );
  final queue = SyncQueueService(database);
  final tasks = TaskRepository(
    database: database,
    syncQueue: queue,
    userId: 'offline-user',
  );
  final existing = await database.select(database.localTasks).get();
  if (existing.isEmpty) {
    await _seed(database, queue, tasks);
  }
  await _ensureLongCourseExample(database, queue);
  final requestedSkin = Uri.base.queryParameters['skin'];
  if (requestedSkin != null) {
    await AppearancePreferencesRepository(database).save(
      AppearancePreferences(
        skin: AppSkinIdX.fromStorage(requestedSkin),
        icon: AppIconStyleX.fromStorage(requestedSkin),
      ),
    );
  }
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(
        const AppConfig(supabaseUrl: '', supabaseAnonKey: ''),
      ),
      appDatabaseProvider.overrideWithValue(database),
      supabaseClientProvider.overrideWithValue(null),
    ],
  );
  container.read(authControllerProvider.notifier).continueOffline();
  runApp(
    UncontrolledProviderScope(container: container, child: const CheckDApp()),
  );
}

Future<void> _ensureLongCourseExample(
  AppDatabase database,
  SyncQueueService queue,
) async {
  const name = '人工智能导论与机器学习算法设计及综合实验';
  final courses = CourseRepository(
    database: database,
    syncQueue: queue,
    userId: 'offline-user',
  );
  if ((await courses.loadCourses()).any((course) => course.name == name)) {
    return;
  }
  final id = await courses.saveCourse(
    CourseDraft(
      name: name,
      classroom: '实验楼 C402',
      colorValue: 0xFF9784C3,
      semester: '2026 秋季学期',
      semesterStartsOn: DateTime(2026, 9, 1),
      semesterEndsOn: DateTime(2027, 1, 20),
    ),
  );
  for (final weekday in [2, 4]) {
    await courses.saveScheduleRule(
      CourseScheduleRuleDraft(
        courseId: id,
        weekday: weekday,
        weekRuleType: CourseWeekRuleType.everyWeek,
        startsAtMinute: 10 * 60 + 30,
        endsAtMinute: 12 * 60,
      ),
    );
  }
}

Future<void> _seed(
  AppDatabase database,
  SyncQueueService queue,
  TaskRepository tasks,
) async {
  final today = dateOnly(DateTime.now());
  final tags = TagRepository(database, 'offline-user', queue);
  final readingTag = await tags.save(name: '阅读', colorValue: 0xFF9784C3);
  final studyTag = await tags.save(name: '自主学习', colorValue: 0xFF7998C4);
  final healthTag = await tags.save(name: '运动', colorValue: 0xFF79A58C);
  final taskIds = <String>[];
  for (final spec in [
    ('阅读半小时', readingTag, 0xFF9784C3, 'book', 1800, null),
    ('英语听力练习', studyTag, 0xFF7998C4, 'headphones', 2400, 19 * 60),
    ('晚间拉伸', healthTag, 0xFF79A58C, 'fitness', 1200, 21 * 60),
  ]) {
    taskIds.add(
      await tasks.saveRecurringTask(
        RecurringTaskDraft(
          name: spec.$1,
          tagId: spec.$2,
          colorValue: spec.$3,
          iconName: spec.$4,
          executionMode: RecurringExecutionMode.timed,
          schedulePreset: SchedulePreset.daily,
          weekdays: {1, 2, 3, 4, 5, 6, 7},
          startsOn: today.subtract(const Duration(days: 14)),
          holidayPause: false,
          targetDurationSeconds: spec.$5,
          scheduledMinuteOfDay: spec.$6,
        ),
      ),
    );
  }
  await tasks.saveOneTimeReminder(
    OneTimeReminderDraft(
      name: '整理数据库课程笔记',
      colorValue: 0xFF7998C4,
      iconName: 'book',
      tagId: studyTag,
      plannedDate: today,
      deadline: TaskDeadline.dateOnly(today.add(const Duration(days: 2))),
      executionMode: OneTimeExecutionMode.timed,
    ),
  );
  await tasks.saveOneTimeReminder(
    OneTimeReminderDraft(
      name: '和小组讨论项目方案',
      colorValue: 0xFFC390A2,
      scheduledAt: today.add(const Duration(hours: 20)),
    ),
  );
  final courses = CourseRepository(
    database: database,
    syncQueue: queue,
    userId: 'offline-user',
  );
  for (final spec in [
    ('高等数学', '理科楼 A203', 8 * 60 + 30, 10 * 60 + 10),
    ('交互设计基础', '设计楼 B305', 14 * 60, 15 * 60 + 40),
  ]) {
    final id = await courses.saveCourse(
      CourseDraft(
        name: spec.$1,
        classroom: spec.$2,
        colorValue: 0xFF7998C4,
        semester: '2026 秋季学期',
        semesterStartsOn: DateTime(2026, 9, 1),
        semesterEndsOn: DateTime(2027, 1, 20),
      ),
    );
    for (final weekday in {1, 3, 5, today.weekday}) {
      await courses.saveScheduleRule(
        CourseScheduleRuleDraft(
          courseId: id,
          weekday: weekday,
          weekRuleType: CourseWeekRuleType.everyWeek,
          startsAtMinute: spec.$3,
          endsAtMinute: spec.$4,
        ),
      );
    }
  }
  for (var day = 6; day >= 0; day--) {
    for (var index = 0; index < taskIds.length; index++) {
      final start = today
          .subtract(Duration(days: day))
          .add(Duration(hours: 7 + index * 2));
      final minutes = [25, 40, 18][index] + day * 3;
      await tasks.startTimer(taskIds[index], now: start.toUtc());
      await tasks.endTimer(
        taskIds[index],
        now: start.add(Duration(minutes: minutes)).toUtc(),
      );
    }
  }
  await tasks.toggleRecurringCompletion(taskIds.first, today);
}
