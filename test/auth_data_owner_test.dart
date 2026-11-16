import 'dart:async';

import 'package:check_d/app/app_providers.dart';
import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/core/sync/sync_upload_service.dart';
import 'package:check_d/features/auth/presentation/auth_controller.dart';
import 'package:check_d/features/courses/application/course_providers.dart';
import 'package:check_d/features/courses/domain/course_models.dart';
import 'package:check_d/features/tasks/application/task_providers.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late StreamController<AuthState> authEvents;
  late ProviderContainer container;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    authEvents = StreamController<AuthState>.broadcast(sync: true);
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        supabaseClientProvider.overrideWithValue(null),
        authStateChangesProvider.overrideWithValue(authEvents.stream),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await authEvents.close();
    await database.close();
  });

  test(
    'owner and repositories follow initial, login, refresh, logout, switch',
    () async {
      expect(container.read(currentDataOwnerProvider), 'offline-user');
      final offlineTasks = container.read(taskRepositoryProvider);
      final offlineCourses = container.read(courseRepositoryProvider);

      // Mirrors Supabase initialSession/signIn events.
      authEvents.add(
        const AuthState(status: AuthStatus.authenticated, userId: 'A'),
      );
      expect(container.read(currentDataOwnerProvider), 'A');
      final tasksA = container.read(taskRepositoryProvider);
      final coursesA = container.read(courseRepositoryProvider);
      expect(identical(tasksA, offlineTasks), isFalse);
      expect(identical(coursesA, offlineCourses), isFalse);

      final taskId = await tasksA.saveOneTimeReminder(
        OneTimeReminderDraft(
          name: 'owner-A task',
          colorValue: 1,
          executionMode: OneTimeExecutionMode.timed,
          deadline: TaskDeadline.dateOnly(DateTime(2026, 12, 1)),
        ),
      );
      final courseId = await coursesA.saveCourse(
        const CourseDraft(name: 'owner-A course', colorValue: 2),
      );
      await tasksA.startTimer(taskId, now: DateTime.utc(2026, 11, 16, 1));
      await tasksA.endTimer(taskId, now: DateTime.utc(2026, 11, 16, 1, 2));

      expect(
        (await database.select(database.localTasks).get()).single.userId,
        'A',
      );
      expect(
        (await database.select(database.courseRecords).get()).single.userId,
        'A',
      );
      expect(
        (await database.select(database.timerSessionRecords).get())
            .single
            .userId,
        'A',
      );
      expect(
        (await database.select(database.syncOperations).get()).every(
          (operation) => operation.userId == 'A',
        ),
        isTrue,
      );
      expect(courseId, isNotEmpty);

      // Token refresh keeps the same owner; logout switches future writes back
      // to offline storage, while old-A repositories stop being provider values.
      authEvents.add(
        const AuthState(status: AuthStatus.authenticated, userId: 'A'),
      );
      expect(container.read(currentDataOwnerProvider), 'A');
      authEvents.add(const AuthState(status: AuthStatus.signedOut));
      expect(container.read(currentDataOwnerProvider), 'offline-user');
      final afterLogout = container.read(taskRepositoryProvider);
      expect(identical(afterLogout, tasksA), isFalse);

      await afterLogout.saveOneTimeReminder(
        OneTimeReminderDraft(name: 'offline remains separate', colorValue: 3),
      );
      authEvents.add(
        const AuthState(status: AuthStatus.authenticated, userId: 'A'),
      );
      final tasksAAgain = container.read(taskRepositoryProvider);
      expect(identical(tasksAAgain, afterLogout), isFalse);

      authEvents.add(
        const AuthState(status: AuthStatus.authenticated, userId: 'B'),
      );
      expect(container.read(currentDataOwnerProvider), 'B');
      final tasksB = container.read(taskRepositoryProvider);
      expect(identical(tasksB, tasksAAgain), isFalse);
      final taskB = await tasksB.saveOneTimeReminder(
        OneTimeReminderDraft(name: 'owner-B task', colorValue: 4),
      );

      final records = await database.select(database.localTasks).get();
      expect(records.singleWhere((row) => row.id == taskId).userId, 'A');
      expect(records.singleWhere((row) => row.id == taskB).userId, 'B');
      final queue = await database.select(database.syncOperations).get();
      expect(
        queue.any((operation) => operation.userId == 'offline-user'),
        isTrue,
      );
      expect(queue.any((operation) => operation.userId == 'A'), isTrue);
      expect(queue.any((operation) => operation.userId == 'B'), isTrue);
    },
  );

  test('user B upload cannot claim user A pending operations', () async {
    expect(container.read(currentDataOwnerProvider), 'offline-user');
    authEvents.add(
      const AuthState(status: AuthStatus.authenticated, userId: 'A'),
    );
    final taskA = await container
        .read(taskRepositoryProvider)
        .saveOneTimeReminder(
          OneTimeReminderDraft(name: 'A pending', colorValue: 1),
        );
    authEvents.add(
      const AuthState(status: AuthStatus.authenticated, userId: 'B'),
    );
    final taskB = await container
        .read(taskRepositoryProvider)
        .saveOneTimeReminder(
          OneTimeReminderDraft(name: 'B pending', colorValue: 2),
        );

    String? activeUser = 'B';
    final remote = _RecordingRemote();
    final executor = SyncUploadExecutor(
      database: database,
      queue: SyncQueueService(database),
      remote: remote,
      currentUserId: () => activeUser,
    );
    final result = await executor.flush(force: true);

    expect(result.failed, 0);
    expect(result.identityMismatch, isFalse);
    expect(remote.owners, isNotEmpty);
    expect(remote.owners, everyElement('B'));
    expect(
      (await database.select(database.syncOperations).get())
          .where((operation) => operation.userId == 'A')
          .every((operation) => operation.status == 'pending'),
      isTrue,
    );
    expect(
      (await database.select(database.syncOperations).get())
          .where((operation) => operation.userId == 'B')
          .every((operation) => operation.status == 'completed'),
      isTrue,
    );
    expect(taskA, isNot(taskB));
  });

  test(
    'an Auth switch during upload stops subsequent old-user writes',
    () async {
      expect(container.read(currentDataOwnerProvider), 'offline-user');
      authEvents.add(
        const AuthState(status: AuthStatus.authenticated, userId: 'A'),
      );
      final repository = container.read(taskRepositoryProvider);
      final first = await repository.saveOneTimeReminder(
        OneTimeReminderDraft(name: 'first', colorValue: 1),
      );
      final second = await repository.saveOneTimeReminder(
        OneTimeReminderDraft(name: 'second', colorValue: 1),
      );

      String? activeUser = 'A';
      final remote = _RecordingRemote(onWrite: () => activeUser = 'B');
      final executor = SyncUploadExecutor(
        database: database,
        queue: SyncQueueService(database),
        remote: remote,
        currentUserId: () => activeUser,
      );
      final result = await executor.flush(force: true);

      expect(result.identityMismatch, isTrue);
      expect(remote.owners, everyElement('A'));
      expect(
        (await database.select(database.syncOperations).get())
            .where((operation) => operation.status == 'pending')
            .length,
        greaterThan(0),
      );
      final tasks = await database.select(database.localTasks).get();
      expect(tasks.where((row) => row.id == first).single.userId, 'A');
      expect(tasks.where((row) => row.id == second).single.userId, 'A');
    },
  );
}

class _RecordingRemote implements SyncRemoteStore {
  _RecordingRemote({this.onWrite});

  final void Function()? onWrite;
  final List<String?> owners = [];

  @override
  Future<void> upsert(
    String table,
    Map<String, Object?> values, {
    required String onConflict,
  }) async {
    owners.add(values['user_id'] as String?);
    onWrite?.call();
  }

  @override
  Future<void> clearOtherActiveFlag(
    String table, {
    required String userId,
    required String id,
    required String flagColumn,
  }) async {
    owners.add(userId);
    onWrite?.call();
  }

  @override
  Future<void> replacePlanTasks({
    required String userId,
    required String planId,
    required List<Map<String, Object?>> rows,
  }) async {
    owners.add(userId);
    onWrite?.call();
  }

  @override
  Future<void> acknowledgeDeviceCheckpoint({
    required String userId,
    required String deviceId,
    required int localGeneration,
  }) async {
    owners.add(userId);
    onWrite?.call();
  }

  @override
  Future<void> publishCourseOccurrenceSnapshot({
    required String userId,
    required String deviceId,
    required Map<String, Object?> snapshot,
  }) async {
    owners.add(userId);
    onWrite?.call();
  }
}
