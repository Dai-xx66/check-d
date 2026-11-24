import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import 'sync_bootstrap_service.dart';
import 'sync_download_service.dart';
import 'sync_upload_service.dart';

enum SyncAccountPhase { idle, restoring, syncing, synced, failed }

enum SyncAccountStage { reading, validating, applying, bootstrap, upload }

class SyncAccountState {
  const SyncAccountState({
    this.phase = SyncAccountPhase.idle,
    this.userId,
    this.lastSuccessAt,
    this.message,
    this.initialRestoreComplete = false,
    this.partialFailure = false,
    this.stage,
    this.restoreTable,
    this.restoreErrorCategory,
    this.restoreSafeCode,
    this.restoreStartedAt,
  });

  final SyncAccountPhase phase;
  final String? userId;
  final DateTime? lastSuccessAt;
  final String? message;
  final bool initialRestoreComplete;
  final bool partialFailure;
  final SyncAccountStage? stage;
  final String? restoreTable;
  final SyncRestoreErrorCategory? restoreErrorCategory;
  final String? restoreSafeCode;
  final DateTime? restoreStartedAt;

  SyncAccountState copyWith({
    SyncAccountPhase? phase,
    String? userId,
    DateTime? lastSuccessAt,
    String? message,
    bool clearMessage = false,
    bool? initialRestoreComplete,
    bool? partialFailure,
    SyncAccountStage? stage,
    String? restoreTable,
    SyncRestoreErrorCategory? restoreErrorCategory,
    String? restoreSafeCode,
    DateTime? restoreStartedAt,
    bool clearRestoreDetails = false,
    bool clearRestoreTable = false,
  }) => SyncAccountState(
    phase: phase ?? this.phase,
    userId: userId ?? this.userId,
    lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
    message: clearMessage ? null : message ?? this.message,
    initialRestoreComplete:
        initialRestoreComplete ?? this.initialRestoreComplete,
    partialFailure: partialFailure ?? this.partialFailure,
    stage: clearRestoreDetails ? null : stage ?? this.stage,
    restoreTable: clearRestoreDetails || clearRestoreTable
        ? null
        : restoreTable ?? this.restoreTable,
    restoreErrorCategory: clearRestoreDetails
        ? null
        : restoreErrorCategory ?? this.restoreErrorCategory,
    restoreSafeCode: clearRestoreDetails
        ? null
        : restoreSafeCode ?? this.restoreSafeCode,
    restoreStartedAt: clearRestoreDetails
        ? null
        : restoreStartedAt ?? this.restoreStartedAt,
  );
}

abstract interface class SyncAccountStatusSink {
  SyncAccountState get current;
  void setState(SyncAccountState next);
}

class SyncAccountStatusController extends Notifier<SyncAccountState>
    implements SyncAccountStatusSink {
  @override
  SyncAccountState build() => const SyncAccountState();

  @override
  void setState(SyncAccountState next) => state = next;

  @override
  SyncAccountState get current => state;
}

final syncAccountStatusProvider =
    NotifierProvider<SyncAccountStatusController, SyncAccountState>(
      SyncAccountStatusController.new,
    );

class SyncAccountRunResult {
  const SyncAccountRunResult({required this.succeeded, this.partial = false});

  final bool succeeded;
  final bool partial;
}

class SyncAccountCoordinator {
  SyncAccountCoordinator({
    required AppDatabase database,
    required SyncDownloadCoordinator download,
    required SyncUploadCoordinator upload,
    required SyncBootstrapService bootstrap,
    required SyncAccountStatusSink status,
    this.uploadWaitTimeout = const Duration(seconds: 30),
  }) : _database = database,
       _download = download,
       _upload = upload,
       _bootstrap = bootstrap,
       _status = status;

  final AppDatabase _database;
  final SyncDownloadCoordinator _download;
  final SyncUploadCoordinator _upload;
  final SyncBootstrapService _bootstrap;
  final SyncAccountStatusSink _status;
  final Duration uploadWaitTimeout;
  Future<SyncAccountRunResult>? _inFlight;
  String? _inFlightUserId;
  String? _activeUserId;
  int _generation = 0;

  Future<SyncAccountRunResult> onAuthenticated(String userId) {
    _activateUser(userId);
    return _run(userId, initial: true);
  }

  Future<SyncAccountRunResult> syncNow(String userId) {
    _activateUser(userId);
    return _run(userId, initial: false, forceDownload: true);
  }

  Future<SyncAccountRunResult> onAppResumed(String userId) {
    _activateUser(userId);
    return _run(userId, initial: false);
  }

  void signedOut() {
    _activeUserId = null;
    _generation++;
    _upload.setActive(false, null);
    _status.setState(const SyncAccountState());
  }

  void _activateUser(String userId) {
    if (_activeUserId == userId) return;
    _activeUserId = userId;
    _generation++;
  }

  Future<SyncAccountRunResult> _run(
    String userId, {
    required bool initial,
    bool forceDownload = false,
  }) {
    if (_inFlight != null) {
      if (_inFlightUserId == userId) return _inFlight!;
      return _inFlight!.then(
        (_) => _run(userId, initial: initial, forceDownload: forceDownload),
      );
    }
    final generation = ++_generation;
    _inFlightUserId = userId;
    return _inFlight =
        _perform(
          userId,
          initial: initial,
          forceDownload: forceDownload,
          generation: generation,
        ).whenComplete(() {
          _inFlight = null;
          _inFlightUserId = null;
        });
  }

  Future<SyncAccountRunResult> _perform(
    String userId, {
    required bool initial,
    required bool forceDownload,
    required int generation,
  }) async {
    final previous = _status.current;
    DateTime? lastSuccess = previous.userId == userId
        ? previous.lastSuccessAt
        : null;
    var gateOpen = previous.userId == userId && previous.initialRestoreComplete;
    final restoreStartedAt = DateTime.now().toUtc();

    try {
      lastSuccess ??= await _readLastSuccess(userId);
      final hasCheckpoint = await _hasInitialRestoreCheckpoint(userId);
      // The legacy marker was written only after download, bootstrap and upload
      // all succeeded, so it is stronger evidence than the new restore-only
      // checkpoint and is safe for upgrade compatibility.
      gateOpen = gateOpen || hasCheckpoint || lastSuccess != null;
      if (!_isCurrent(userId, generation)) {
        return const SyncAccountRunResult(succeeded: false);
      }
      _status.setState(
        SyncAccountState(
          phase: gateOpen
              ? SyncAccountPhase.syncing
              : SyncAccountPhase.restoring,
          userId: userId,
          lastSuccessAt: lastSuccess,
          initialRestoreComplete: gateOpen,
          stage: SyncAccountStage.reading,
          restoreStartedAt: restoreStartedAt,
        ),
      );

      void reportProgress(SyncRestoreProgress progress) {
        if (!_isCurrent(userId, generation)) return;
        _status.setState(
          _status.current.copyWith(
            stage: _accountStage(progress.stage),
            restoreTable: progress.table,
            clearRestoreTable: progress.table == null,
          ),
        );
      }

      final restored = initial
          ? await _download.onAuthenticated(userId, onProgress: reportProgress)
          : forceDownload
          ? await _download.reconcileIfDue(
              force: true,
              onProgress: reportProgress,
            )
          : await _download.onAppResumed(onProgress: reportProgress);
      if (!_isCurrent(userId, generation)) {
        return const SyncAccountRunResult(succeeded: false);
      }
      if (!restored.succeeded) {
        final failure = restored.failure;
        _status.setState(
          SyncAccountState(
            phase: SyncAccountPhase.failed,
            userId: userId,
            lastSuccessAt: lastSuccess,
            message: _restoreFailureMessage(failure),
            initialRestoreComplete: gateOpen,
            stage: failure == null
                ? _status.current.stage
                : _accountStage(failure.stage),
            restoreTable: failure?.table,
            restoreErrorCategory: failure?.category,
            restoreSafeCode: failure?.safeCode,
            restoreStartedAt: restoreStartedAt,
          ),
        );
        return const SyncAccountRunResult(succeeded: false);
      }

      DateTime? checkpointWrittenAt;
      if (!gateOpen) {
        checkpointWrittenAt = DateTime.now().toUtc();
        await _writeInitialRestoreCheckpoint(userId, checkpointWrittenAt);
      }
      if (!_isCurrent(userId, generation)) {
        if (checkpointWrittenAt != null) {
          await _removeInitialRestoreCheckpointIfValue(
            userId,
            checkpointWrittenAt,
          );
        }
        return const SyncAccountRunResult(succeeded: false);
      }

      _status.setState(
        SyncAccountState(
          phase: SyncAccountPhase.syncing,
          userId: userId,
          lastSuccessAt: lastSuccess,
          initialRestoreComplete: true,
          stage: SyncAccountStage.bootstrap,
          restoreStartedAt: restoreStartedAt,
        ),
      );
      unawaited(
        _finishBackgroundSync(
          userId,
          generation: generation,
          lastSuccess: lastSuccess,
          restoreStartedAt: restoreStartedAt,
        ),
      );
      return const SyncAccountRunResult(succeeded: true);
    } on Object {
      if (_isCurrent(userId, generation)) {
        _status.setState(
          SyncAccountState(
            phase: SyncAccountPhase.failed,
            userId: userId,
            lastSuccessAt: lastSuccess,
            message: '同步状态准备失败，请重试。',
            initialRestoreComplete: gateOpen,
            restoreErrorCategory: SyncRestoreErrorCategory.localDatabase,
            restoreSafeCode: 'local_state',
            restoreStartedAt: restoreStartedAt,
          ),
        );
      }
      return const SyncAccountRunResult(succeeded: false);
    }
  }

  Future<void> _finishBackgroundSync(
    String userId, {
    required int generation,
    required DateTime? lastSuccess,
    required DateTime restoreStartedAt,
  }) async {
    try {
      await _bootstrap.bootstrap(userId);
      if (!_isCurrent(userId, generation)) return;
      _status.setState(
        _status.current.copyWith(
          phase: SyncAccountPhase.syncing,
          stage: SyncAccountStage.upload,
          clearMessage: true,
          initialRestoreComplete: true,
        ),
      );

      final uploaded = await _upload
          .flush(force: true)
          .timeout(uploadWaitTimeout);
      if (!_isCurrent(userId, generation)) return;
      _upload.setActive(true, userId);
      if (uploaded.busy) {
        _status.setState(
          SyncAccountState(
            phase: SyncAccountPhase.syncing,
            userId: userId,
            lastSuccessAt: lastSuccess,
            message: '后台同步正在继续。',
            initialRestoreComplete: true,
            stage: SyncAccountStage.upload,
            restoreStartedAt: restoreStartedAt,
          ),
        );
        return;
      }
      if (uploaded.unauthenticated) {
        _status.setState(
          SyncAccountState(
            phase: SyncAccountPhase.failed,
            userId: userId,
            lastSuccessAt: lastSuccess,
            message: '登录状态已失效，请重新登录后再试。',
            initialRestoreComplete: true,
            stage: SyncAccountStage.upload,
            restoreStartedAt: restoreStartedAt,
          ),
        );
        return;
      }
      if (uploaded.failed > 0) {
        _status.setState(
          SyncAccountState(
            phase: SyncAccountPhase.failed,
            userId: userId,
            lastSuccessAt: lastSuccess,
            message: '部分数据同步失败，稍后会自动重试。',
            initialRestoreComplete: true,
            partialFailure: true,
            stage: SyncAccountStage.upload,
            restoreStartedAt: restoreStartedAt,
          ),
        );
        return;
      }

      final now = DateTime.now().toUtc();
      await _writeLastSuccess(userId, now);
      if (!_isCurrent(userId, generation)) return;
      _status.setState(
        SyncAccountState(
          phase: SyncAccountPhase.synced,
          userId: userId,
          lastSuccessAt: now,
          initialRestoreComplete: true,
          restoreStartedAt: restoreStartedAt,
        ),
      );
    } on TimeoutException {
      if (!_isCurrent(userId, generation)) return;
      _upload.setActive(true, userId);
      _status.setState(
        SyncAccountState(
          phase: SyncAccountPhase.failed,
          userId: userId,
          lastSuccessAt: lastSuccess,
          message: '后台上传超时，稍后会自动重试。',
          initialRestoreComplete: true,
          partialFailure: true,
          stage: SyncAccountStage.upload,
          restoreErrorCategory: SyncRestoreErrorCategory.timeout,
          restoreSafeCode: 'upload_timeout',
          restoreStartedAt: restoreStartedAt,
        ),
      );
    } on Object {
      if (!_isCurrent(userId, generation)) return;
      _upload.setActive(true, userId);
      _status.setState(
        SyncAccountState(
          phase: SyncAccountPhase.failed,
          userId: userId,
          lastSuccessAt: lastSuccess,
          message: '后台同步失败，稍后会自动重试。',
          initialRestoreComplete: true,
          partialFailure: true,
          restoreStartedAt: restoreStartedAt,
        ),
      );
    }
  }

  SyncAccountStage _accountStage(SyncRestoreStage stage) => switch (stage) {
    SyncRestoreStage.reading => SyncAccountStage.reading,
    SyncRestoreStage.validating => SyncAccountStage.validating,
    SyncRestoreStage.applying => SyncAccountStage.applying,
  };

  String _restoreFailureMessage(SyncRestoreFailure? failure) {
    if (failure?.category == SyncRestoreErrorCategory.timeout) {
      return failure?.table == null
          ? '云端数据恢复超时，请检查网络后重试。'
          : '读取云端数据超时，请检查网络后重试。';
    }
    if (failure?.category == SyncRestoreErrorCategory.authentication) {
      return '登录状态已失效，请重新登录后再试。';
    }
    if (failure?.category == SyncRestoreErrorCategory.conflict) {
      return '本机存在其他账号的数据冲突，未执行覆盖。';
    }
    if (failure?.category == SyncRestoreErrorCategory.accountChanged) {
      return '账号已切换，已停止旧账号的数据恢复。';
    }
    return '云端数据恢复失败，请检查网络后重试。';
  }

  bool _isCurrent(String userId, int generation) =>
      _activeUserId == userId && _generation == generation;

  String _lastSuccessKey(String userId) => 'sync-last-success:$userId';

  String _initialRestoreKey(String userId) =>
      'sync-initial-restore-complete:$userId';

  Future<bool> _hasInitialRestoreCheckpoint(String userId) async {
    final row =
        await (_database.select(_database.appSettings)
              ..where((item) => item.key.equals(_initialRestoreKey(userId))))
            .getSingleOrNull();
    return row != null;
  }

  Future<void> _writeInitialRestoreCheckpoint(String userId, DateTime value) {
    return _database
        .into(_database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: _initialRestoreKey(userId),
            value: value.toIso8601String(),
            updatedAt: value,
          ),
        );
  }

  Future<void> _removeInitialRestoreCheckpointIfValue(
    String userId,
    DateTime value,
  ) {
    return (_database.delete(_database.appSettings)..where(
          (item) =>
              item.key.equals(_initialRestoreKey(userId)) &
              item.value.equals(value.toIso8601String()),
        ))
        .go();
  }

  Future<DateTime?> _readLastSuccess(String userId) async {
    final row =
        await (_database.select(_database.appSettings)
              ..where((item) => item.key.equals(_lastSuccessKey(userId))))
            .getSingleOrNull();
    return row == null ? null : DateTime.tryParse(row.value)?.toLocal();
  }

  Future<void> _writeLastSuccess(String userId, DateTime value) {
    return _database
        .into(_database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: _lastSuccessKey(userId),
            value: value.toIso8601String(),
            updatedAt: value,
          ),
        );
  }
}
