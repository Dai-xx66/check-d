import 'course_share_schema.dart';

class CourseShareConfig {
  const CourseShareConfig({
    this.defaultExpiry = const Duration(days: 7),
    this.allowedExpiries = const [Duration(days: 7), Duration(days: 30)],
    this.maxCourses = 50,
    this.maxPayloadBytes = 64 * 1024,
    this.codeLength = 8,
    this.codeGroupLength = 4,
  });

  final Duration defaultExpiry;
  final List<Duration> allowedExpiries;
  final int maxCourses;
  final int maxPayloadBytes;
  final int codeLength;
  final int codeGroupLength;
}

enum CourseShareErrorCategory {
  invalidCode,
  expired,
  notFound,
  unsupportedSchema,
  networkUnavailable,
  serverUnavailable,
  corruptedPayload,
  authenticationRequired,
  packageTooLarge,
  tooManyCourses,
}

class CourseShareException implements Exception {
  const CourseShareException(this.category, this.message);

  final CourseShareErrorCategory category;
  final String message;

  @override
  String toString() => message;
}

class CreatedCourseShare {
  const CreatedCourseShare({required this.code, required this.expiresAt});

  final String code;
  final DateTime expiresAt;

  String get deepLink => 'checkd://share/${CourseShareCode.compact(code)}';
}

class FetchedCourseShare {
  const FetchedCourseShare({
    required this.code,
    required this.expiresAt,
    required this.package,
  });

  final String code;
  final DateTime expiresAt;
  final SharePackage package;
}

abstract final class CourseShareCode {
  static final RegExp _valid = RegExp(r'^[A-HJ-KM-NP-Z2-9]{8}$');

  static String compact(String value) =>
      value.trim().toUpperCase().replaceAll(RegExp(r'[\s-]'), '');

  static bool isValid(String value) => _valid.hasMatch(compact(value));

  static String display(String value, {int groupLength = 4}) {
    final normalized = compact(value);
    if (normalized.length <= groupLength) return normalized;
    return [
      for (var index = 0; index < normalized.length; index += groupLength)
        normalized.substring(
          index,
          (index + groupLength).clamp(0, normalized.length),
        ),
    ].join('-');
  }

  static String fromQrValue(String value) {
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed);
    String candidate = trimmed;
    if (uri != null && uri.scheme.toLowerCase() == 'checkd') {
      if (uri.host.toLowerCase() != 'share' || uri.pathSegments.isEmpty) {
        throw const CourseShareException(
          CourseShareErrorCategory.invalidCode,
          '这不是有效的 Check D 课程分享二维码。',
        );
      }
      candidate = uri.pathSegments.first;
    }
    if (!isValid(candidate)) {
      throw const CourseShareException(
        CourseShareErrorCategory.invalidCode,
        '分享口令格式不正确。',
      );
    }
    return compact(candidate);
  }
}
