import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import 'sync_apply_scope.dart';

enum SyncOperationType { upsert, archive }

class SyncOperationHealth {
  const SyncOperationHealth({
    required this.pending,
    required this.failed,
    this.lastFailureAt,
  });

  final int pending;
  final int failed;
  final DateTime? lastFailureAt;
}

class SyncFailureDiagnostic {
  const SyncFailureDiagnostic({
    required this.entityType,
    required this.retryCount,
    required this.errorCategory,
    required this.lastFailureAt,
    this.failureStage,
    this.failureTable,
    this.errorCode,
  });

  final String entityType;
  final int retryCount;
  final String errorCategory;
  final String? failureStage;
  final String? failureTable;
  final String? errorCode;
  final DateTime lastFailureAt;
}

class SyncFailureDetails implements Exception {
  const SyncFailureDetails({
    required this.stage,
    required this.table,
    required this.kind,
    this.code,
  });

  static const _version = 1;

  final String stage;
  final String table;
  final String kind;
  final String? code;

  String encode() => jsonEncode({
    'version': _version,
    'stage': stage,
    'table': table,
    'kind': kind,
    if (code != null) 'code': code,
  });
}

class SyncQueueService {
  SyncQueueService(this._database, {SyncApplyScope? applyScope})
    : _applyScope = applyScope;

  final AppDatabase _database;
  final SyncApplyScope? _applyScope;
  final Uuid _uuid = const Uuid();

  Future<void> enqueue({
    required String entityType,
    required String entityId,
    required SyncOperationType operation,
    required Map<String, Object?> payload,
    String? userId,
  }) async {
    if (_applyScope?.isApplying ?? false) return;
    final now = DateTime.now().toUtc();
    await _database
        .into(_database.syncOperations)
        .insert(
          SyncOperationsCompanion.insert(
            id: _uuid.v4(),
            userId: Value(userId),
            entityType: entityType,
            entityId: entityId,
            operation: operation.name,
            payloadJson: jsonEncode(payload),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Stream<List<SyncOperation>> watchPending() {
    final query = _database.select(_database.syncOperations)
      ..where((row) => row.status.equals('pending'))
      ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]);
    return query.watch();
  }

  Future<List<SyncOperation>> loadRetryableForUser(
    String userId, {
    int limit = 100,
  }) {
    final query = _database.select(_database.syncOperations)
      ..where(
        (row) =>
            row.userId.equals(userId) &
            (row.status.equals('pending') | row.status.equals('failed')),
      )
      // New work must not be hidden behind a full batch of permanent failures.
      // An attempted failure updates updatedAt, rotating retries fairly; the
      // executor still applies dependency ordering and retry backoff.
      ..orderBy([
        (row) => OrderingTerm.desc(row.status.equals('pending')),
        (row) => OrderingTerm.asc(row.updatedAt),
        (row) => OrderingTerm.asc(row.createdAt),
      ])
      ..limit(limit);
    return query.get();
  }

  Stream<List<SyncOperation>> watchRetryableForUser(String userId) {
    final query = _database.select(_database.syncOperations)
      ..where(
        (row) =>
            row.userId.equals(userId) &
            (row.status.equals('pending') | row.status.equals('failed')),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]);
    return query.watch();
  }

  Stream<SyncOperationHealth> watchHealthForUser(String userId) {
    final query = _database.select(_database.syncOperations)
      ..where(
        (row) =>
            row.userId.equals(userId) &
            (row.status.equals('pending') | row.status.equals('failed')),
      )
      ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]);
    return query.watch().map((rows) {
      final failed = rows.where((row) => row.status == 'failed').toList();
      return SyncOperationHealth(
        pending: rows.length - failed.length,
        failed: failed.length,
        lastFailureAt: failed.isEmpty ? null : failed.first.updatedAt,
      );
    });
  }

  Stream<List<SyncFailureDiagnostic>> watchFailureDiagnosticsForUser(
    String userId,
  ) {
    final query = _database.select(_database.syncOperations)
      ..where((row) => row.userId.equals(userId) & row.status.equals('failed'))
      ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]);
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          _diagnostic(
            entityType: row.entityType,
            retryCount: row.retryCount,
            lastError: row.lastError,
            updatedAt: row.updatedAt,
          ),
      ],
    );
  }

  Future<void> markCompleted(String operationId) {
    final now = DateTime.now().toUtc();
    return (_database.update(
      _database.syncOperations,
    )..where((row) => row.id.equals(operationId))).write(
      SyncOperationsCompanion(
        status: const Value('completed'),
        lastError: const Value(null),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> markFailed(String operationId, Object error) {
    final now = DateTime.now().toUtc();
    final message = error is SyncFailureDetails
        ? error.encode()
        : error.toString();
    return (_database.update(
      _database.syncOperations,
    )..where((row) => row.id.equals(operationId))).write(
      SyncOperationsCompanion.custom(
        status: const Constant('failed'),
        retryCount: const CustomExpression<int>('retry_count + 1'),
        lastError: Variable<String>(
          message.length > 500 ? message.substring(0, 500) : message,
        ),
        updatedAt: Variable<DateTime>(now),
      ),
    );
  }

  SyncFailureDiagnostic _diagnostic({
    required String entityType,
    required int retryCount,
    required String? lastError,
    required DateTime updatedAt,
  }) {
    final structured = _structuredFailure(lastError);
    final safeCode = structured?.code ?? _safeErrorCode(lastError);
    final fallbackCategory = _safeFallbackCategory(lastError);
    return SyncFailureDiagnostic(
      entityType: entityType,
      retryCount: retryCount,
      errorCategory:
          structured == null && safeCode == null && fallbackCategory == '未知同步错误'
          ? '历史错误信息不足'
          : _safeErrorCategory(lastError, safeCode, kind: structured?.kind),
      failureStage: structured?.stage,
      failureTable: structured?.table,
      errorCode: safeCode,
      lastFailureAt: updatedAt,
    );
  }

  _StructuredSyncFailure? _structuredFailure(String? error) {
    if (error == null || !error.trimLeft().startsWith('{')) return null;
    try {
      final value = jsonDecode(error);
      if (value is! Map<String, Object?> || value['version'] != 1) return null;
      final stage = _safeIdentifier(value['stage']);
      final table = _safeIdentifier(value['table']);
      final kind = _safeIdentifier(value['kind']);
      if (stage == null || table == null || kind == null) return null;
      return _StructuredSyncFailure(
        stage: stage,
        table: table,
        kind: kind,
        code: _validatedErrorCode(value['code']?.toString()),
      );
    } on FormatException {
      return null;
    }
  }

  String? _safeIdentifier(Object? value) {
    final text = value?.toString();
    if (text == null || !RegExp(r'^[a-z0-9_]{1,64}$').hasMatch(text)) {
      return null;
    }
    return text;
  }

  String? _safeErrorCode(String? error) {
    if (error == null) return null;
    final match = RegExp(
      r'''(?:code\s*[:=]\s*|["']code["']\s*:\s*["'])([A-Za-z0-9_]+)''',
      caseSensitive: false,
    ).firstMatch(error);
    return _validatedErrorCode(match?.group(1));
  }

  String? _validatedErrorCode(String? value) {
    final code = value?.toUpperCase();
    if (code == null ||
        !RegExp(r'^(?:[A-Z0-9]{5}|PGRST[0-9]{3})$').hasMatch(code)) {
      return null;
    }
    return code;
  }

  String _safeErrorCategory(String? error, String? code, {String? kind}) {
    if (kind == 'network') return '网络连接失败';
    if (kind == 'local_state') return '本地记录状态不一致';
    if (kind == 'serialization') return '同步数据序列化失败';
    if (kind == 'auth') return '登录或授权状态异常';
    return switch (code) {
      '22003' => '数值超出云端字段范围',
      '22P02' => '上传数据格式不匹配',
      '22007' || '22008' => '日期或时间格式不匹配',
      '23502' => '云端必填字段缺失',
      '23503' => '云端关联数据缺失',
      '23505' => '云端唯一约束冲突',
      '23514' => '上传数据不符合云端约束',
      '42501' => '云端访问权限被拒绝',
      '42703' => '云端字段尚未对齐',
      '42804' => '云端字段类型不匹配',
      '42P01' => '云端数据表不存在',
      final value when value != null && value.startsWith('08') => '云端数据库连接失败',
      final value when value != null && value.startsWith('PGRST') =>
        '云端 API Schema 不匹配',
      _ => _safeFallbackCategory(error),
    };
  }

  String _safeFallbackCategory(String? error) {
    final normalized = error?.toLowerCase() ?? '';
    if (normalized.contains('socketexception') ||
        normalized.contains('clientexception') ||
        normalized.contains('connection reset') ||
        normalized.contains('timed out') ||
        normalized.contains('timeout') ||
        normalized.contains('handshakeexception')) {
      return '网络连接失败';
    }
    if (normalized.contains('jwt') ||
        normalized.contains('auth') ||
        normalized.contains('unauthorized')) {
      return '登录或授权状态异常';
    }
    if (normalized.contains('no longer exists locally') ||
        normalized.contains('not found locally')) {
      return '本地记录状态不一致';
    }
    if (normalized.contains('unsupported sync entity')) {
      return '当前版本不支持该同步类型';
    }
    return '未知同步错误';
  }
}

class _StructuredSyncFailure {
  const _StructuredSyncFailure({
    required this.stage,
    required this.table,
    required this.kind,
    this.code,
  });

  final String stage;
  final String table;
  final String kind;
  final String? code;
}
