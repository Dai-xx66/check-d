import 'dart:convert';
import 'dart:math';

import '../domain/course_share_models.dart';
import '../domain/course_import_models.dart';
import '../domain/course_share_schema.dart';

abstract interface class CourseShareRepository {
  Future<CreatedCourseShare> createShare(
    SharePackage package, {
    Duration? expiry,
  });

  Future<FetchedCourseShare> fetchShare(String code);

  Future<void> deleteShare(String code);
}

enum CourseShareRemoteStatus { found, notFound, expired }

class CourseShareRemoteRecord {
  const CourseShareRemoteRecord({
    required this.status,
    this.code,
    this.expiresAt,
    this.payload,
  });

  final CourseShareRemoteStatus status;
  final String? code;
  final DateTime? expiresAt;
  final String? payload;
}

abstract interface class CourseShareRemoteStore {
  bool get canCreate;

  Future<bool> create({
    required String code,
    required int schemaVersion,
    required String payload,
    required DateTime expiresAt,
  });

  Future<CourseShareRemoteRecord> fetch(String code);

  Future<void> delete(String code);
}

class CourseShareRemoteException implements Exception {
  const CourseShareRemoteException({required this.networkUnavailable});

  final bool networkUnavailable;
}

class DefaultCourseShareRepository implements CourseShareRepository {
  DefaultCourseShareRepository({
    required CourseShareRemoteStore remote,
    CourseShareConfig config = const CourseShareConfig(),
    Random? random,
    DateTime Function()? now,
  }) : _remote = remote,
       _config = config,
       _random = random ?? Random.secure(),
       _now = now ?? DateTime.now;

  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const _maxCodeAttempts = 6;

  final CourseShareRemoteStore _remote;
  final CourseShareConfig _config;
  final Random _random;
  final DateTime Function() _now;

  @override
  Future<CreatedCourseShare> createShare(
    SharePackage package, {
    Duration? expiry,
  }) async {
    if (!_remote.canCreate) {
      throw const CourseShareException(
        CourseShareErrorCategory.authenticationRequired,
        '请先登录后再创建课程分享。',
      );
    }
    final duration = expiry ?? _config.defaultExpiry;
    if (!_config.allowedExpiries.contains(duration)) {
      throw const CourseShareException(
        CourseShareErrorCategory.serverUnavailable,
        '不支持该分享有效期。',
      );
    }
    if (package.payload.courses.isEmpty) {
      throw const CourseShareException(
        CourseShareErrorCategory.corruptedPayload,
        '分享中没有可用课程。',
      );
    }
    if (package.payload.courses.length > _config.maxCourses) {
      throw CourseShareException(
        CourseShareErrorCategory.tooManyCourses,
        '一次最多分享 ${_config.maxCourses} 门课程。',
      );
    }
    final encoded = package.encode();
    if (utf8.encode(encoded).length > _config.maxPayloadBytes) {
      throw const CourseShareException(
        CourseShareErrorCategory.packageTooLarge,
        '分享内容过大，请减少课程数量或备注后重试。',
      );
    }
    final expiresAt = _now().toUtc().add(duration);
    try {
      for (var attempt = 0; attempt < _maxCodeAttempts; attempt++) {
        final code = _generateCode();
        final created = await _remote.create(
          code: code,
          schemaVersion: package.payload.schemaVersion,
          payload: encoded,
          expiresAt: expiresAt,
        );
        if (created) {
          return CreatedCourseShare(
            code: CourseShareCode.display(
              code,
              groupLength: _config.codeGroupLength,
            ),
            expiresAt: expiresAt,
          );
        }
      }
    } on CourseShareRemoteException catch (error) {
      throw _remoteFailure(error);
    }
    throw const CourseShareException(
      CourseShareErrorCategory.serverUnavailable,
      '暂时无法生成唯一分享口令，请稍后重试。',
    );
  }

  @override
  Future<FetchedCourseShare> fetchShare(String code) async {
    final normalized = CourseShareCode.compact(code);
    if (!CourseShareCode.isValid(normalized)) {
      throw const CourseShareException(
        CourseShareErrorCategory.invalidCode,
        '分享口令格式不正确。',
      );
    }
    try {
      final record = await _remote.fetch(normalized);
      if (record.status == CourseShareRemoteStatus.notFound) {
        throw const CourseShareException(
          CourseShareErrorCategory.notFound,
          '没有找到这个分享口令。',
        );
      }
      if (record.status == CourseShareRemoteStatus.expired) {
        throw const CourseShareException(
          CourseShareErrorCategory.expired,
          '这个课程分享已经过期。',
        );
      }
      final payload = record.payload;
      final expiresAt = record.expiresAt;
      if (payload == null || expiresAt == null) {
        throw const CourseShareException(
          CourseShareErrorCategory.corruptedPayload,
          '分享内容不完整。',
        );
      }
      if (!expiresAt.isAfter(_now().toUtc())) {
        throw const CourseShareException(
          CourseShareErrorCategory.expired,
          '这个课程分享已经过期。',
        );
      }
      try {
        return FetchedCourseShare(
          code: CourseShareCode.display(normalized),
          expiresAt: expiresAt,
          package: SharePackage.decode(payload),
        );
      } on CourseImportException catch (error) {
        throw CourseShareException(
          error.category == CourseImportErrorCategory.unsupportedFormat
              ? CourseShareErrorCategory.unsupportedSchema
              : CourseShareErrorCategory.corruptedPayload,
          error.message,
        );
      } on CourseShareException {
        rethrow;
      } catch (_) {
        throw const CourseShareException(
          CourseShareErrorCategory.corruptedPayload,
          '分享内容已损坏。',
        );
      }
    } on CourseShareRemoteException catch (error) {
      throw _remoteFailure(error);
    } on CourseShareException {
      rethrow;
    }
  }

  @override
  Future<void> deleteShare(String code) async {
    final normalized = CourseShareCode.compact(code);
    if (!CourseShareCode.isValid(normalized)) return;
    try {
      await _remote.delete(normalized);
    } on CourseShareRemoteException catch (error) {
      throw _remoteFailure(error);
    }
  }

  String _generateCode() => String.fromCharCodes([
    for (var index = 0; index < _config.codeLength; index++)
      _alphabet.codeUnitAt(_random.nextInt(_alphabet.length)),
  ]);

  CourseShareException _remoteFailure(CourseShareRemoteException error) =>
      CourseShareException(
        error.networkUnavailable
            ? CourseShareErrorCategory.networkUnavailable
            : CourseShareErrorCategory.serverUnavailable,
        error.networkUnavailable
            ? '当前无法获取分享内容，请检查网络后重试。'
            : '课程分享服务暂时不可用，请稍后重试。',
      );
}
