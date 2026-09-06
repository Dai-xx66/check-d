import 'package:check_d/app/app.dart';
import 'package:check_d/app/app_providers.dart';
import 'package:check_d/core/config/app_config.dart';
import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/calendar/presentation/calendar_page.dart';
import 'package:check_d/features/courses/application/course_providers.dart';
import 'package:check_d/features/courses/domain/course_models.dart';
import 'package:check_d/features/schedule/application/day_schedule_providers.dart';
import 'package:check_d/features/schedule/domain/day_schedule_models.dart';
import 'package:check_d/features/statistics/application/statistics_providers.dart';
import 'package:check_d/features/statistics/domain/statistics_models.dart';
import 'package:check_d/features/tasks/application/task_providers.dart';
import 'package:check_d/features/tasks/data/task_repository.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('zh_CN'));

  testWidgets('offline entry opens the app shell', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(supabaseUrl: '', supabaseAnonKey: ''),
          ),
          appDatabaseProvider.overrideWithValue(database),
          supabaseClientProvider.overrideWithValue(null),
          dailyTimerStateProvider.overrideWith(
            (ref, date) => Stream.value(
              TaskTimerState(sessions: const [], localDate: date),
            ),
          ),
          tasksForDateProvider.overrideWith(
            (ref, date) => Stream.value(const <TaskDetails>[]),
          ),
          coursesSnapshotProvider.overrideWith(
            (ref) => Future.value(const <CourseDetails>[]),
          ),
          dailyOverridesSnapshotProvider.overrideWith(
            (ref, date) => Future.value(const <DailyItemOverride>[]),
          ),
          adHocTimersForDateProvider.overrideWith(
            (ref, date) => Stream.value(const <AdHocTimerDetails>[]),
          ),
        ],
        child: const CheckDApp(),
      ),
    );

    expect(find.text('离线体验'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, '离线体验'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('今日完成度'), findsOneWidget);
    expect(find.text('今日待完成'), findsOneWidget);
    expect(find.text('三日日程'), findsOneWidget);
    expect(find.text('今日总结'), findsOneWidget);
    expect(find.text('连续打卡'), findsOneWidget);
    expect(find.text('周期任务'), findsNothing);
    expect(find.text('单次事项'), findsNothing);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('复盘'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('mobile today splits pending and precisely scheduled items', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final today = dateOnly(DateTime.now());
    final createdAt = DateTime(2026);
    final pending = TaskDetails(
      id: 'pending',
      name: '背单词',
      kind: TaskKind.recurring,
      colorValue: 0xFF9B8BE8,
      status: TaskLifecycle.active,
      createdAt: createdAt,
      updatedAt: createdAt,
      recurringMode: RecurringExecutionMode.timed,
      targetDurationSeconds: 1800,
    );
    final scheduled = TaskDetails(
      id: 'scheduled',
      name: '数据库作业',
      kind: TaskKind.oneTime,
      colorValue: 0xFFEF8FA8,
      status: TaskLifecycle.active,
      createdAt: createdAt,
      updatedAt: createdAt,
      scheduledAt: DateTime(today.year, today.month, today.day, 14),
      oneTimeExecutionMode: OneTimeExecutionMode.untimed,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(supabaseUrl: '', supabaseAnonKey: ''),
          ),
          appDatabaseProvider.overrideWithValue(database),
          supabaseClientProvider.overrideWithValue(null),
          dailyTimerStateProvider.overrideWith(
            (ref, date) => Stream.value(
              TaskTimerState(sessions: const [], localDate: date),
            ),
          ),
          tasksForDateProvider.overrideWith((ref, date) {
            if (dateOnly(date) == today) {
              return Stream.value([pending, scheduled]);
            }
            return Stream.value(const <TaskDetails>[]);
          }),
          coursesSnapshotProvider.overrideWith(
            (ref) => Future.value(const <CourseDetails>[]),
          ),
          dailyOverridesSnapshotProvider.overrideWith(
            (ref, date) => Future.value(const <DailyItemOverride>[]),
          ),
          adHocTimersForDateProvider.overrideWith(
            (ref, date) => Stream.value(const <AdHocTimerDetails>[]),
          ),
        ],
        child: const CheckDApp(),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, '离线体验'));
    await tester.pumpAndSettle();

    expect(find.text('今日待完成'), findsOneWidget);
    expect(find.text('背单词'), findsWidgets);
    expect(find.text('数据库作业'), findsWidgets);
    expect(find.text('周期任务'), findsNothing);
    expect(find.text('单次事项'), findsNothing);

    await tester.drag(find.byType(PageView), const Offset(-320, 0));
    await tester.pumpAndSettle();
    expect(find.text('明日待完成'), findsOneWidget);
    expect(find.text('回到今天'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('desktop width uses the desktop sidebar', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(supabaseUrl: '', supabaseAnonKey: ''),
          ),
          appDatabaseProvider.overrideWithValue(database),
          supabaseClientProvider.overrideWithValue(null),
          dailyTimerStateProvider.overrideWith(
            (ref, date) => Stream.value(
              TaskTimerState(sessions: const [], localDate: date),
            ),
          ),
          tasksForDateProvider.overrideWith(
            (ref, date) => Stream.value(const <TaskDetails>[]),
          ),
        ],
        child: const CheckDApp(),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, '离线体验'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('快速创建'), findsOneWidget);
    expect(find.text('立即开始计时'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('desktop pending timed task starts without opening details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = TaskRepository(
      database: database,
      syncQueue: SyncQueueService(database),
      userId: 'offline-user',
    );
    final today = dateOnly(DateTime.now());
    await repository.saveRecurringTask(
      RecurringTaskDraft(
        name: '桌面待安排计时',
        colorValue: 0xFF9B8BE8,
        executionMode: RecurringExecutionMode.timed,
        targetDurationSeconds: 1800,
        schedulePreset: SchedulePreset.daily,
        weekdays: WeekdayMask.toDays(WeekdayMask.everyDay),
        startsOn: today,
        holidayPause: false,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(supabaseUrl: '', supabaseAnonKey: ''),
          ),
          appDatabaseProvider.overrideWithValue(database),
          supabaseClientProvider.overrideWithValue(null),
          taskRepositoryProvider.overrideWithValue(repository),
        ],
        child: const CheckDApp(),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, '离线体验'));
    await tester.pumpAndSettle();

    expect(find.text('桌面待安排计时'), findsOneWidget);
    expect(find.text('开始'), findsOneWidget);
    await tester.tap(find.text('开始'));
    await tester.pumpAndSettle();

    expect((await repository.getUnfinishedTimers()), hasLength(1));
    expect(find.text('暂停'), findsOneWidget);
    expect(find.text('进行中'), findsOneWidget);

    await tester.tap(find.text('暂停'));
    await tester.pumpAndSettle();
    expect(find.text('已暂停'), findsOneWidget);
    expect(find.text('继续'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('mobile calendar opens the selected day details', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final today = dateOnly(DateTime.now());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          statisticsDataProvider.overrideWith(
            (ref) => Stream.value(
              const StatisticsData(
                tags: [],
                sessions: [],
                tasks: [],
                reminderCompletions: [],
              ),
            ),
          ),
          appConfigProvider.overrideWithValue(
            const AppConfig(supabaseUrl: '', supabaseAnonKey: ''),
          ),
          appDatabaseProvider.overrideWithValue(database),
          supabaseClientProvider.overrideWithValue(null),
          dailyTimerStateProvider.overrideWith(
            (ref, date) => Stream.value(
              TaskTimerState(sessions: const [], localDate: date),
            ),
          ),
          tasksForDateProvider.overrideWith(
            (ref, date) => Stream.value(const <TaskDetails>[]),
          ),
          calendarMonthProvider.overrideWith(
            (ref, month) =>
                Stream.value(CalendarMonthData(month: month, days: const [])),
          ),
        ],
        child: const CheckDApp(),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, '离线体验'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('${today.day}').first);
    await tester.pumpAndSettle();

    expect(find.text('当天详情'), findsOneWidget);
    expect(find.text('当天完成度'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('desktop calendar keeps day details beside the month', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final month = DateTime(DateTime.now().year, DateTime.now().month);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          statisticsDataProvider.overrideWith(
            (ref) => Stream.value(
              const StatisticsData(
                tags: [],
                sessions: [],
                tasks: [],
                reminderCompletions: [],
              ),
            ),
          ),
          calendarMonthProvider.overrideWith(
            (ref, value) =>
                Stream.value(CalendarMonthData(month: value, days: const [])),
          ),
          dailyTimerStateProvider.overrideWith(
            (ref, date) => Stream.value(
              TaskTimerState(sessions: const [], localDate: date),
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: CalendarPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('日历'), findsOneWidget);
    expect(find.text('${month.year}年 ${month.month}月'), findsOneWidget);
    expect(find.text('当天完成度'), findsOneWidget);
  });
}
