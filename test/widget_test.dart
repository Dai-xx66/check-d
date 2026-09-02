import 'package:check_d/app/app.dart';
import 'package:check_d/app/app_providers.dart';
import 'package:check_d/core/config/app_config.dart';
import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/features/calendar/presentation/calendar_page.dart';
import 'package:check_d/features/tasks/application/task_providers.dart';
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
          tasksForDateProvider.overrideWith(
            (ref, date) => Stream.value(const <TaskDetails>[]),
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
    expect(find.text('单次事项提醒'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('desktop width uses the navigation rail', (tester) async {
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

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
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
          appConfigProvider.overrideWithValue(
            const AppConfig(supabaseUrl: '', supabaseAnonKey: ''),
          ),
          appDatabaseProvider.overrideWithValue(database),
          supabaseClientProvider.overrideWithValue(null),
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
          calendarMonthProvider.overrideWith(
            (ref, value) =>
                Stream.value(CalendarMonthData(month: value, days: const [])),
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
