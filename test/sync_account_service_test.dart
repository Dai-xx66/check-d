import 'dart:async';

import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_account_service.dart';
import 'package:check_d/core/sync/sync_apply_scope.dart';
import 'package:check_d/core/sync/sync_bootstrap_service.dart';
import 'package:check_d/core/sync/sync_download_service.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/core/sync/sync_upload_service.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const userId = 'user-1';
  late AppDatabase database;
  late SyncQueueService queue;
  late _RemoteReader reader;
  late _StatusSink status;
  late SyncUploadCoordinator upload;
  late _RemoteStore remoteStore;
  late SyncAccountCoordinator account;
  late String? authenticatedUserId;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    queue = SyncQueueService(database);
    reader = _RemoteReader();
    status = _StatusSink();
    authenticatedUserId = userId;
    remoteStore = _RemoteStore();
    upload = SyncUploadCoordinator(
      SyncUploadExecutor(
        database: database,
        queue: queue,
        remote: remoteStore,
        currentUserId: () => authenticatedUserId,
      ),
      queue,
    );
    account = SyncAccountCoordinator(
      database: database,
      download: SyncDownloadCoordinator(
        SyncDownloadExecutor(
          database: database,
          remote: reader,
          applyScope: SyncApplyScope(),
          currentUserId: () => authenticatedUserId,
        ),
      ),
      upload: upload,
      bootstrap: SyncBootstrapService(database, queue),
      status: status,
    );
  });

  tearDown(() async {
    upload.dispose();
    await database.close();
  });

  test('initial restore exposes loading state before showing data', () async {
    reader.blockNextRead();

    final run = account.onAuthenticated(userId);
    await Future<void>.delayed(Duration.zero);
    expect(status.current.phase, SyncAccountPhase.restoring);
    expect(status.current.initialRestoreComplete, isFalse);

    reader.release();
    expect((await run).succeeded, isTrue);
    expect(status.current.initialRestoreComplete, isTrue);
    await _waitFor(() => status.current.phase == SyncAccountPhase.synced);
  });

  test('restore failure is visible and retry can succeed', () async {
    reader.fail = true;

    expect((await account.onAuthenticated(userId)).succeeded, isFalse);
    expect(status.current.phase, SyncAccountPhase.failed);
    expect(status.current.initialRestoreComplete, isFalse);
    expect(status.current.message, contains('恢复失败'));

    reader.fail = false;
    expect((await account.syncNow(userId)).succeeded, isTrue);
    expect(status.current.initialRestoreComplete, isTrue);
    await _waitFor(() => status.current.phase == SyncAccountPhase.synced);
  });

  test('sign out does not delete local business data', () async {
    final now = DateTime.utc(2030);
    await database
        .into(database.localTasks)
        .insert(
          LocalTasksCompanion.insert(
            id: 'keep-me',
            userId: const Value(userId),
            name: '保留事项',
            taskType: 'recurring',
            colorValue: 1,
            createdAt: now,
            updatedAt: now,
          ),
        );

    account.signedOut();

    expect(await database.select(database.localTasks).get(), hasLength(1));
    expect(status.current.phase, SyncAccountPhase.idle);
  });

  test('authenticated restore never adopts offline-user rows', () async {
    await _insertOwnedTask(database, 'offline-task', 'offline-user');

    expect((await account.onAuthenticated(userId)).succeeded, isTrue);
    await _waitFor(() => status.current.phase == SyncAccountPhase.synced);

    final local = await (database.select(
      database.localTasks,
    )..where((row) => row.id.equals('offline-task'))).getSingle();
    expect(local.userId, 'offline-user');
    final userOwned = await (database.select(
      database.localTasks,
    )..where((row) => row.userId.equals(userId))).get();
    expect(userOwned, isEmpty);
  });

  test('logging into B invalidates an in-flight session for A', () async {
    await _insertOwnedTask(database, 'task-a', 'user-a');
    reader.blockNextRead();
    authenticatedUserId = 'user-a';
    final userARun = account.onAuthenticated('user-a');
    await Future<void>.delayed(Duration.zero);

    account.signedOut();
    authenticatedUserId = 'user-b';
    final userBRun = account.onAuthenticated('user-b');
    reader.release();

    expect((await userARun).succeeded, isFalse);
    expect((await userBRun).succeeded, isTrue);
    await _waitFor(() => status.current.phase == SyncAccountPhase.synced);
    expect(status.current.userId, 'user-b');
    final operations = await database.select(database.syncOperations).get();
    expect(operations.where((row) => row.userId == 'user-a'), isEmpty);
  });

  test('per-UID restore checkpoint survives coordinator recreation', () async {
    expect((await account.onAuthenticated(userId)).succeeded, isTrue);
    await _waitFor(() => status.current.phase == SyncAccountPhase.synced);

    final secondStatus = _StatusSink();
    final secondReader = _RemoteReader()..blockNextRead();
    final secondAccount = SyncAccountCoordinator(
      database: database,
      download: SyncDownloadCoordinator(
        SyncDownloadExecutor(
          database: database,
          remote: secondReader,
          applyScope: SyncApplyScope(),
          currentUserId: () => authenticatedUserId,
        ),
      ),
      upload: upload,
      bootstrap: SyncBootstrapService(database, queue),
      status: secondStatus,
    );

    final coldStart = secondAccount.onAuthenticated(userId);
    await _waitFor(
      () => secondStatus.current.phase == SyncAccountPhase.syncing,
    );

    expect(secondStatus.current.initialRestoreComplete, isTrue);
    secondReader.release();
    expect((await coldStart).succeeded, isTrue);
    await _waitFor(() => secondStatus.current.phase == SyncAccountPhase.synced);
  });

  test('legacy last-success is accepted only for the same UID', () async {
    final now = DateTime.utc(2030, 1, 2);
    await database
        .into(database.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: 'sync-last-success:$userId',
            value: now.toIso8601String(),
            updatedAt: now,
          ),
        );
    reader.blockNextRead();

    final run = account.onAuthenticated(userId);
    await _waitFor(() => status.current.phase == SyncAccountPhase.syncing);
    expect(status.current.initialRestoreComplete, isTrue);

    reader.release();
    expect((await run).succeeded, isTrue);
    await _waitFor(() => status.current.phase == SyncAccountPhase.synced);

    account.signedOut();
    authenticatedUserId = 'user-2';
    reader.blockNextRead();
    final other = account.onAuthenticated('user-2');
    await _waitFor(() => status.current.phase == SyncAccountPhase.restoring);

    expect(status.current.userId, 'user-2');
    expect(status.current.initialRestoreComplete, isFalse);
    final userBMarker =
        await (database.select(database.appSettings)..where(
              (row) => row.key.equals('sync-initial-restore-complete:user-2'),
            ))
            .getSingleOrNull();
    expect(userBMarker, null);

    reader.release();
    expect((await other).succeeded, isTrue);
    await _waitFor(() => status.current.phase == SyncAccountPhase.synced);
  });

  test(
    'table timeout closes loading state and exposes safe metadata',
    () async {
      final timeoutReader = _RemoteReader()..blockNextRead();
      account = SyncAccountCoordinator(
        database: database,
        download: SyncDownloadCoordinator(
          SyncDownloadExecutor(
            database: database,
            remote: timeoutReader,
            applyScope: SyncApplyScope(),
            currentUserId: () => authenticatedUserId,
            tableReadTimeout: const Duration(milliseconds: 5),
            restoreTimeout: const Duration(seconds: 1),
          ),
        ),
        upload: upload,
        bootstrap: SyncBootstrapService(database, queue),
        status: status,
      );

      expect((await account.onAuthenticated(userId)).succeeded, isFalse);

      expect(status.current.phase, SyncAccountPhase.failed);
      expect(status.current.initialRestoreComplete, isFalse);
      expect(
        status.current.restoreErrorCategory,
        SyncRestoreErrorCategory.timeout,
      );
      expect(status.current.restoreTable, 'tags');
      expect(status.current.message, isNot(contains('StateError')));
      timeoutReader.release();
    },
  );

  test('download success opens the gate before a hanging upload', () async {
    await _insertOwnedTask(database, 'upload-me', userId);
    remoteStore.blockUpserts();

    expect((await account.onAuthenticated(userId)).succeeded, isTrue);
    await _waitFor(() => status.current.stage == SyncAccountStage.upload);

    expect(status.current.initialRestoreComplete, isTrue);
    expect(status.current.phase, SyncAccountPhase.syncing);
    remoteStore.release();
    await _waitFor(() => status.current.phase == SyncAccountPhase.synced);
  });

  test(
    'permanently pending upload times out without relocking AppShell',
    () async {
      await _insertOwnedTask(database, 'upload-timeout', userId);
      remoteStore.blockUpserts();
      account = SyncAccountCoordinator(
        database: database,
        download: SyncDownloadCoordinator(
          SyncDownloadExecutor(
            database: database,
            remote: reader,
            applyScope: SyncApplyScope(),
            currentUserId: () => authenticatedUserId,
          ),
        ),
        upload: upload,
        bootstrap: SyncBootstrapService(database, queue),
        status: status,
        uploadWaitTimeout: const Duration(milliseconds: 5),
      );

      expect((await account.onAuthenticated(userId)).succeeded, isTrue);
      await _waitFor(() => status.current.phase == SyncAccountPhase.failed);

      expect(status.current.initialRestoreComplete, isTrue);
      expect(status.current.restoreSafeCode, 'upload_timeout');
      remoteStore.release();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    },
  );

  test('upload failure remains visible without relocking the gate', () async {
    await _insertOwnedTask(database, 'upload-fails', userId);
    remoteStore.fail = true;

    expect((await account.onAuthenticated(userId)).succeeded, isTrue);
    await _waitFor(() => status.current.phase == SyncAccountPhase.failed);

    expect(status.current.initialRestoreComplete, isTrue);
    expect(status.current.partialFailure, isTrue);
  });

  test(
    'late background upload from A cannot overwrite B account state',
    () async {
      authenticatedUserId = 'user-a';
      await _insertOwnedTask(database, 'task-a-upload', 'user-a');
      remoteStore.blockUpserts();
      expect((await account.onAuthenticated('user-a')).succeeded, isTrue);
      await _waitFor(() => status.current.stage == SyncAccountStage.upload);

      account.signedOut();
      authenticatedUserId = 'user-b';
      expect((await account.onAuthenticated('user-b')).succeeded, isTrue);
      expect(status.current.userId, 'user-b');
      expect(status.current.initialRestoreComplete, isTrue);

      remoteStore.release();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(status.current.userId, 'user-b');
    },
  );

  test('resume never relocks an account with a restore checkpoint', () async {
    expect((await account.onAuthenticated(userId)).succeeded, isTrue);
    await _waitFor(() => status.current.phase == SyncAccountPhase.synced);
    reader.blockNextRead();

    final resumed = account.onAppResumed(userId);
    await Future<void>.delayed(Duration.zero);

    expect(status.current.initialRestoreComplete, isTrue);
    reader.release();
    await resumed;
    await _waitFor(() => status.current.phase == SyncAccountPhase.synced);
  });
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('test condition was not reached');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

Future<void> _insertOwnedTask(AppDatabase database, String id, String owner) {
  final now = DateTime.utc(2030);
  return database
      .into(database.localTasks)
      .insert(
        LocalTasksCompanion.insert(
          id: id,
          userId: Value(owner),
          name: id,
          taskType: 'recurring',
          colorValue: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );
}

class _StatusSink implements SyncAccountStatusSink {
  @override
  SyncAccountState current = const SyncAccountState();

  @override
  void setState(SyncAccountState next) => current = next;
}

class _RemoteReader implements SyncRemoteReader {
  bool fail = false;
  Completer<void>? _blocker;

  void blockNextRead() => _blocker = Completer<void>();
  void release() => _blocker?.complete();

  @override
  Future<List<Map<String, Object?>>> readTable(
    String table, {
    required String userId,
  }) async {
    final blocker = _blocker;
    if (blocker != null && !blocker.isCompleted) await blocker.future;
    _blocker = null;
    if (fail) throw StateError('network unavailable');
    return const [];
  }
}

class _RemoteStore implements SyncRemoteStore {
  bool fail = false;
  Completer<void>? _upsertBlocker;

  void blockUpserts() => _upsertBlocker = Completer<void>();

  void release() {
    final blocker = _upsertBlocker;
    if (blocker != null && !blocker.isCompleted) blocker.complete();
  }

  @override
  Future<void> clearOtherActiveFlag(
    String table, {
    required String userId,
    required String id,
    required String flagColumn,
  }) async {}

  @override
  Future<void> replacePlanTasks({
    required String userId,
    required String planId,
    required List<Map<String, Object?>> rows,
  }) async {}

  @override
  Future<void> acknowledgeDeviceCheckpoint({
    required String userId,
    required String deviceId,
    required int localGeneration,
  }) async {}

  @override
  Future<void> publishCourseOccurrenceSnapshot({
    required String userId,
    required String deviceId,
    required Map<String, Object?> snapshot,
  }) async {}

  @override
  Future<void> upsert(
    String table,
    Map<String, Object?> values, {
    required String onConflict,
  }) async {
    final blocker = _upsertBlocker;
    if (blocker != null && !blocker.isCompleted) await blocker.future;
    if (fail) throw StateError('raw secret-shaped upload failure');
  }
}
