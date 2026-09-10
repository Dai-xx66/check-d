import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../domain/course_models.dart';
import '../domain/course_schedule_import_models.dart';

class CourseScheduleRecognitionUnavailable implements Exception {
  const CourseScheduleRecognitionUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class CourseScheduleRecognizer {
  Future<CourseScheduleRecognitionResult> recognize({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  });
}

/// Calls a server-side Supabase Edge Function. There is no client-side API key:
/// the function is responsible for its own configured recognition provider.
class SupabaseCourseScheduleRecognizer implements CourseScheduleRecognizer {
  SupabaseCourseScheduleRecognizer(this._client);
  final SupabaseClient? _client;

  @override
  Future<CourseScheduleRecognitionResult> recognize({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    final client = _client;
    if (client == null) {
      throw const CourseScheduleRecognitionUnavailable('识别服务尚未连接，请先完成账号与网络配置。');
    }
    try {
      final response = await client.functions.invoke(
        'recognize-course-schedule',
        body: {
          'filename': filename,
          'mimeType': mimeType,
          'imageBase64': base64Encode(bytes),
        },
      );
      final data = response.data;
      if (data is! Map) {
        throw const CourseScheduleRecognitionUnavailable('识别服务返回的数据格式无效。');
      }
      return _parse(Map<String, dynamic>.from(data));
    } on FunctionException catch (error) {
      final details = error.details;
      final message = details is Map ? details['error']?.toString() : null;
      throw CourseScheduleRecognitionUnavailable(message ?? '识别服务暂不可用，请稍后重试。');
    }
  }

  CourseScheduleRecognitionResult _parse(Map<String, dynamic> value) {
    final rawCourses = value['courses'];
    if (rawCourses is! List) {
      throw const CourseScheduleRecognitionUnavailable('未从图片中识别到可用课程。');
    }
    final courses = <RecognizedCourseDraft>[];
    for (final raw in rawCourses.whereType<Map>()) {
      final course = Map<String, dynamic>.from(raw);
      final rules = <RecognizedScheduleRuleDraft>[];
      for (final rawRule
          in (course['rules'] as List? ?? const []).whereType<Map>()) {
        final rule = Map<String, dynamic>.from(rawRule);
        final parsedWeekRule = _weekRule(rule['weekRuleType']?.toString());
        rules.add(
          RecognizedScheduleRuleDraft(
            weekday: _asInt(rule['weekday']),
            recognizedSectionNumbers: _intList(rule['sections']),
            weekRuleType: parsedWeekRule,
            startWeek: _asInt(rule['startWeek']),
            endWeek: _asInt(rule['endWeek']),
            intervalWeeks: _asInt(rule['intervalWeeks']),
            weekNumbers: _intList(rule['weekNumbers']).toSet(),
            recognizedStartsAtMinute: _asInt(rule['startsAtMinute']),
            recognizedEndsAtMinute: _asInt(rule['endsAtMinute']),
            weekRuleConfirmed: parsedWeekRule != null,
            warnings: parsedWeekRule == null
                ? const [
                    CourseImportWarning(
                      CourseImportWarningKind.unconfirmedWeekRule,
                      '周次信息请确认',
                    ),
                  ]
                : const [],
          ),
        );
      }
      courses.add(
        RecognizedCourseDraft(
          id: const Uuid().v4(),
          name: course['name']?.toString() ?? '',
          teacher: course['teacher']?.toString(),
          classroom: course['classroom']?.toString(),
          rules: rules,
        ),
      );
    }
    final segments = <RecognizedScheduleSegmentDraft>[];
    for (final raw
        in (value['segments'] as List? ?? const []).whereType<Map>()) {
      final segment = Map<String, dynamic>.from(raw);
      final number = _asInt(segment['number']);
      final start = _asInt(segment['startsAtMinute']);
      final end = _asInt(segment['endsAtMinute']);
      if (number != null && start != null && end != null && end > start) {
        segments.add(
          RecognizedScheduleSegmentDraft(
            number: number,
            startsAtMinute: start,
            endsAtMinute: end,
          ),
        );
      }
    }
    return CourseScheduleRecognitionResult(
      courses: courses,
      detectedSegments: segments,
    );
  }

  CourseWeekRuleType? _weekRule(String? value) => switch (value) {
    'everyWeek' => CourseWeekRuleType.everyWeek,
    'oddWeeks' => CourseWeekRuleType.oddWeeks,
    'evenWeeks' => CourseWeekRuleType.evenWeeks,
    'everyNWeeks' => CourseWeekRuleType.everyNWeeks,
    'custom' => CourseWeekRuleType.custom,
    _ => null,
  };

  int? _asInt(Object? value) => value is int ? value : int.tryParse('$value');
  List<int> _intList(Object? value) =>
      (value as List? ?? const []).map(_asInt).whereType<int>().toList();
}
