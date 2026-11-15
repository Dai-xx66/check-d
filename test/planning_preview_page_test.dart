import 'dart:convert';

import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/courses/data/course_repository.dart';
import 'package:check_d/features/courses/data/semester_repository.dart';
import 'package:check_d/features/courses/domain/course_models.dart';
import 'package:check_d/features/planning/application/planning_providers.dart';
import 'package:check_d/features/planning/data/planning_context_repository.dart';
import 'package:check_d/features/planning/data/planning_preview_client.dart';
import 'package:check_d/features/planning/presentation/planning_preview_page.dart';
import 'package:check_d/features/schedule/data/day_schedule_repository.dart';
import 'package:check_d/features/tasks/data/task_repository.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets(
    'logged-in Drift context renders preview and delay comparison safely',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final queue = SyncQueueService(database);
      final tasks = TaskRepository(
        database: database,
        syncQueue: queue,
        userId: 'test-user-a',
      );
      final courses = CourseRepository(
        database: database,
        syncQueue: queue,
        userId: 'test-user-a',
      );
      final semesters = SemesterRepository(
        database: database,
        syncQueue: queue,
        userId: 'test-user-a',
      );
      final schedule = DayScheduleRepository(
        database: database,
        syncQueue: queue,
        userId: 'test-user-a',
      );
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final courseId = await courses.saveCourse(
        CourseDraft(name: '隔离测试课程', colorValue: 0, semesterStartsOn: tomorrow),
      );
      await courses.saveScheduleRule(
        CourseScheduleRuleDraft(
          courseId: courseId,
          weekday: tomorrow.weekday,
          weekRuleType: CourseWeekRuleType.everyWeek,
          startsAtMinute: 12 * 60,
          endsAtMinute: 13 * 60,
        ),
      );
      await tasks.saveOneTimeReminder(
        OneTimeReminderDraft(name: '隔离测试单次事项', colorValue: 0),
      );
      final repository = PlanningContextRepository(
        database: database,
        tasks: tasks,
        courses: courses,
        semesters: semesters,
        schedule: schedule,
        authenticatedUserId: 'test-user-a',
      );

      final mockHttpClient = MockClient((request) async {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        final snapshot = (payload['snapshot'] as Map).cast<String, dynamic>();
        final task = (snapshot['tasks'] as List).cast<Map>().single;
        final hasInputs =
            task['remaining_seconds'] != null &&
            (task['deadline_date'] != null || task['deadline_at'] != null);
        Map<String, Object?> response;
        if (request.url.path == '/v0/preview') {
          response = {
            'ok': true,
            'snapshot_version': snapshot['version'],
            'outcome': hasInputs
                ? 'found_feasible'
                : 'unknown_due_to_missing_data',
            'execution_eligible': false,
            'schedule': {
              'feasible': hasInputs,
              'blocks': hasInputs
                  ? [
                      {
                        'task_id': task['task_id'],
                        'starts_at':
                            '${DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 13).toIso8601String()}+08:00',
                        'ends_at':
                            '${DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 14).toIso8601String()}+08:00',
                      },
                    ]
                  : [],
            },
            'missing_data': {
              'unknown_effort_task_ids': hasInputs ? [] : [task['task_id']],
              'missing_deadline_task_ids': hasInputs ? [] : [task['task_id']],
              'existing_plan_needing_effort_task_ids': [],
              'unmodeled_recurring_occurrence_ids': [],
            },
          };
        } else if (request.url.path == '/v0/risks') {
          response = {'ok': true, 'risks': []};
        } else {
          response = {
            'ok': true,
            'delay_analysis': {
              'before_feasible': true,
              'after_feasible': true,
              'slack_change_seconds': -3600,
            },
          };
        }
        return http.Response(jsonEncode(response), 200);
      });
      final client = PlanningPreviewClient(
        baseUrl: 'http://local-preview.test',
        token: 'widget-local-bridge-test-token-123456789',
        client: mockHttpClient,
      );
      addTearDown(client.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            planningContextRepositoryProvider.overrideWithValue(repository),
            planningPreviewClientProvider.overrideWithValue(client),
          ],
          child: const MaterialApp(home: PlanningPreviewPage()),
        ),
      );
      await _pumpUntil(tester, find.textContaining('剩余工作量未知'));
      expect(find.text('智能规划预览'), findsOneWidget);
      expect(find.textContaining('有待同步的本地变更'), findsOneWidget);
      expect(find.textContaining('未知值不会被补成默认时长'), findsOneWidget);

      await tester.ensureVisible(find.textContaining('补充本次预览参数'));
      await tester.tap(find.textContaining('补充本次预览参数'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '60');
      await tester.tap(find.text('选择截止日期'));
      await tester.pumpAndSettle();
      final confirmDate = find.text('OK');
      await tester.tap(
        confirmDate.evaluate().isNotEmpty ? confirmDate : find.text('确定'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('仅用于本次预览'));
      await _pumpUntil(tester, find.text('当前输入下找到可行候选安排。'));

      expect(find.textContaining('仅用于本次计算'), findsOneWidget);
      expect(find.text('隔离测试单次事项'), findsWidgets);
      await tester.ensureVisible(find.textContaining('明天再做'));
      await tester.tap(find.textContaining('明天再做').first);
      await _pumpUntil(tester, find.textContaining('延期前：'));
      expect(find.textContaining('延期后：'), findsOneWidget);
    },
  );
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}
