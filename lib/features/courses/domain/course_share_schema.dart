import 'dart:convert';

import 'course_import_models.dart';
import 'course_models.dart';

enum ShareSchemaCompatibility { supported, requiresMigration, unsupported }

abstract final class ShareSchemaVersion {
  static const int current = 1;

  static ShareSchemaCompatibility compatibility(int version) {
    if (version == current) return ShareSchemaCompatibility.supported;
    if (version > 0 && version < current) {
      return ShareSchemaCompatibility.requiresMigration;
    }
    return ShareSchemaCompatibility.unsupported;
  }

  static bool isSupported(int version) =>
      compatibility(version) == ShareSchemaCompatibility.supported;
}

class SharePayload {
  const SharePayload({
    required this.schemaVersion,
    required this.sourceApp,
    required this.exportedAt,
    required this.courses,
    this.semester,
  });

  final int schemaVersion;
  final String sourceApp;
  final DateTime exportedAt;
  final ShareSemester? semester;
  final List<ShareCourse> courses;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'sourceApp': sourceApp,
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    if (semester != null) 'semester': semester!.toJson(),
    'courses': courses.map((course) => course.toJson()).toList(),
  };

  factory SharePayload.fromJson(Map<String, Object?> json) {
    final version = _int(json['schemaVersion']);
    final compatibility = version == null
        ? ShareSchemaCompatibility.unsupported
        : ShareSchemaVersion.compatibility(version);
    if (compatibility != ShareSchemaCompatibility.supported) {
      throw const CourseImportException(
        CourseImportErrorCategory.unsupportedFormat,
        '不支持的 Check D 分享数据版本。',
      );
    }
    final rawCourses = json['courses'];
    if (rawCourses is! List) {
      throw const CourseImportException(
        CourseImportErrorCategory.invalidDraft,
        '分享数据缺少课程列表。',
      );
    }
    try {
      return SharePayload(
        schemaVersion: version!,
        sourceApp: _requiredString(json['sourceApp'], 'sourceApp'),
        exportedAt: DateTime.parse(
          _requiredString(json['exportedAt'], 'exportedAt'),
        ),
        semester: json['semester'] is Map
            ? ShareSemester.fromJson(
                Map<String, Object?>.from(json['semester']! as Map),
              )
            : null,
        courses: rawCourses
            .map(
              (value) =>
                  ShareCourse.fromJson(Map<String, Object?>.from(value as Map)),
            )
            .toList(),
      );
    } on CourseImportException {
      rethrow;
    } catch (_) {
      throw const CourseImportException(
        CourseImportErrorCategory.invalidDraft,
        'Check D 分享数据格式无效。',
      );
    }
  }
}

class ShareSemester {
  const ShareSemester({
    required this.name,
    required this.firstWeekStartDate,
    required this.totalWeeks,
  });

  final String name;
  final DateTime firstWeekStartDate;
  final int totalWeeks;

  Map<String, Object?> toJson() => {
    'name': name,
    'firstWeekStartDate': _date(firstWeekStartDate),
    'totalWeeks': totalWeeks,
  };

  factory ShareSemester.fromJson(Map<String, Object?> json) => ShareSemester(
    name: _requiredString(json['name'], 'semester.name'),
    firstWeekStartDate: DateTime.parse(
      _requiredString(
        json['firstWeekStartDate'],
        'semester.firstWeekStartDate',
      ),
    ),
    totalWeeks: _requiredInt(json['totalWeeks'], 'semester.totalWeeks'),
  );
}

class ShareCourse {
  const ShareCourse({
    required this.title,
    required this.colorValue,
    required this.scheduleRules,
    this.teacher,
    this.classroom,
    this.note,
  });

  final String title;
  final String? teacher;
  final String? classroom;
  final int colorValue;
  final String? note;
  final List<ShareScheduleRule> scheduleRules;

  Map<String, Object?> toJson() => {
    'title': title,
    if (_notBlank(teacher)) 'teacher': teacher,
    if (_notBlank(classroom)) 'classroom': classroom,
    'colorValue': colorValue,
    if (_notBlank(note)) 'note': note,
    'scheduleRules': scheduleRules.map((rule) => rule.toJson()).toList(),
  };

  factory ShareCourse.fromJson(Map<String, Object?> json) {
    final rawRules = json['scheduleRules'];
    if (rawRules is! List) {
      throw const CourseImportException(
        CourseImportErrorCategory.invalidDraft,
        '分享课程缺少课程安排。',
      );
    }
    return ShareCourse(
      title: _requiredString(json['title'], 'course.title'),
      teacher: _string(json['teacher']),
      classroom: _string(json['classroom']),
      colorValue: _requiredInt(json['colorValue'], 'course.colorValue'),
      note: _string(json['note']),
      scheduleRules: rawRules
          .map(
            (value) => ShareScheduleRule.fromJson(
              Map<String, Object?>.from(value as Map),
            ),
          )
          .toList(),
    );
  }
}

class ShareScheduleRule {
  const ShareScheduleRule({
    required this.weekday,
    required this.startsAtMinute,
    required this.endsAtMinute,
    required this.weekRuleType,
    this.startWeek,
    this.endWeek,
    this.intervalWeeks,
    this.customWeeks = const {},
    this.segments = const [],
    this.classroomOverride,
    this.note,
  });

  final int weekday;
  final int startsAtMinute;
  final int endsAtMinute;
  final CourseWeekRuleType weekRuleType;
  final int? startWeek;
  final int? endWeek;
  final int? intervalWeeks;
  final Set<int> customWeeks;
  final List<ShareScheduleSegment> segments;
  final String? classroomOverride;
  final String? note;

  Map<String, Object?> toJson() => {
    'weekday': weekday,
    'startsAtMinute': startsAtMinute,
    'endsAtMinute': endsAtMinute,
    'weekRule': weekRuleType.name,
    if (startWeek != null) 'startWeek': startWeek,
    if (endWeek != null) 'endWeek': endWeek,
    if (intervalWeeks != null) 'intervalWeeks': intervalWeeks,
    if (customWeeks.isNotEmpty) 'customWeeks': (customWeeks.toList()..sort()),
    if (segments.isNotEmpty)
      'segments': segments.map((segment) => segment.toJson()).toList(),
    if (_notBlank(classroomOverride)) 'classroomOverride': classroomOverride,
    if (_notBlank(note)) 'note': note,
  };

  factory ShareScheduleRule.fromJson(Map<String, Object?> json) =>
      ShareScheduleRule(
        weekday: _requiredInt(json['weekday'], 'rule.weekday'),
        startsAtMinute: _requiredInt(
          json['startsAtMinute'],
          'rule.startsAtMinute',
        ),
        endsAtMinute: _requiredInt(json['endsAtMinute'], 'rule.endsAtMinute'),
        weekRuleType: CourseWeekRuleType.values.byName(
          _requiredString(json['weekRule'], 'rule.weekRule'),
        ),
        startWeek: _int(json['startWeek']),
        endWeek: _int(json['endWeek']),
        intervalWeeks: _int(json['intervalWeeks']),
        customWeeks: _intSet(json['customWeeks']),
        segments: (json['segments'] as List? ?? const [])
            .map(
              (value) => ShareScheduleSegment.fromJson(
                Map<String, Object?>.from(value as Map),
              ),
            )
            .toList(),
        classroomOverride: _string(json['classroomOverride']),
        note: _string(json['note']),
      );
}

class ShareScheduleSegment {
  const ShareScheduleSegment({
    required this.label,
    required this.startsAtMinute,
    required this.endsAtMinute,
    required this.order,
  });

  final String label;
  final int startsAtMinute;
  final int endsAtMinute;
  final int order;

  Map<String, Object?> toJson() => {
    'label': label,
    'startsAtMinute': startsAtMinute,
    'endsAtMinute': endsAtMinute,
    'order': order,
  };

  factory ShareScheduleSegment.fromJson(Map<String, Object?> json) =>
      ShareScheduleSegment(
        label: _requiredString(json['label'], 'segment.label'),
        startsAtMinute: _requiredInt(
          json['startsAtMinute'],
          'segment.startsAtMinute',
        ),
        endsAtMinute: _requiredInt(
          json['endsAtMinute'],
          'segment.endsAtMinute',
        ),
        order: _requiredInt(json['order'], 'segment.order'),
      );
}

class SharePackage {
  const SharePackage(this.payload);

  final SharePayload payload;

  factory SharePackage.fromDraft(
    CourseImportDraft draft, {
    DateTime? exportedAt,
    bool includeNotes = true,
  }) {
    final semester = draft.semester;
    return SharePackage(
      SharePayload(
        schemaVersion: ShareSchemaVersion.current,
        sourceApp: 'Check D',
        exportedAt: exportedAt ?? DateTime.now().toUtc(),
        semester: semester == null
            ? null
            : ShareSemester(
                name: semester.name,
                firstWeekStartDate: semester.firstWeekStartDate,
                totalWeeks: semester.totalWeeks,
              ),
        courses: [
          for (final course in draft.courses.where((item) => item.selected))
            ShareCourse(
              title: course.title,
              teacher: course.teacher,
              classroom: course.classroom,
              colorValue: course.colorValue,
              note: includeNotes ? course.note : null,
              scheduleRules: [
                for (final rule in course.scheduleRules)
                  ShareScheduleRule(
                    weekday: rule.weekday!,
                    startsAtMinute: rule.startsAtMinute!,
                    endsAtMinute: rule.endsAtMinute!,
                    weekRuleType: rule.weekRuleType!,
                    startWeek: rule.startWeek,
                    endWeek: rule.endWeek,
                    intervalWeeks: rule.intervalWeeks,
                    customWeeks: rule.customWeeks,
                    classroomOverride: rule.classroomOverride,
                    note: includeNotes ? rule.note : null,
                    segments: [
                      for (final segment in rule.segments)
                        if (segment.startsAtMinute != null &&
                            segment.endsAtMinute != null)
                          ShareScheduleSegment(
                            label: segment.label,
                            startsAtMinute: segment.startsAtMinute!,
                            endsAtMinute: segment.endsAtMinute!,
                            order: segment.order,
                          ),
                    ],
                  ),
              ],
            ),
        ],
      ),
    );
  }

  String encode() => jsonEncode(payload.toJson());

  factory SharePackage.decode(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) {
        throw const CourseImportException(
          CourseImportErrorCategory.invalidDraft,
          '分享数据不是有效的对象。',
        );
      }
      return SharePackage(
        SharePayload.fromJson(Map<String, Object?>.from(decoded)),
      );
    } on CourseImportException {
      rethrow;
    } catch (_) {
      throw const CourseImportException(
        CourseImportErrorCategory.parseFailed,
        '无法解析 Check D 分享数据。',
      );
    }
  }

  CourseImportDraft toImportDraft() {
    final semester = payload.semester;
    return CourseImportDraft(
      schemaVersion: CourseImportDraft.currentSchemaVersion,
      sourceType: CourseImportSourceType.shareCode,
      semester: semester == null
          ? null
          : CourseImportSemesterCandidate(
              name: semester.name,
              firstWeekStartDate: semester.firstWeekStartDate,
              totalWeeks: semester.totalWeeks,
            ),
      courses: [
        for (var index = 0; index < payload.courses.length; index++)
          _toImportCourse(payload.courses[index], index),
      ],
    );
  }

  CourseImportCourseDraft _toImportCourse(ShareCourse course, int index) =>
      CourseImportCourseDraft(
        importKey: 'share-$index',
        title: course.title,
        teacher: course.teacher,
        classroom: course.classroom,
        colorValue: course.colorValue,
        note: course.note,
        scheduleRules: [
          for (final rule in course.scheduleRules)
            CourseImportScheduleRuleDraft(
              weekday: rule.weekday,
              startsAtMinute: rule.startsAtMinute,
              endsAtMinute: rule.endsAtMinute,
              weekRuleType: rule.weekRuleType,
              startWeek: rule.startWeek,
              endWeek: rule.endWeek,
              intervalWeeks: rule.intervalWeeks,
              customWeeks: rule.customWeeks,
              timeMode: rule.segments.isEmpty
                  ? CourseScheduleTimeMode.customTime
                  : CourseScheduleTimeMode.periods,
              classroomOverride: rule.classroomOverride,
              note: rule.note,
              segments: [
                for (final segment in rule.segments)
                  CourseImportSegmentCandidate(
                    label: segment.label,
                    startsAtMinute: segment.startsAtMinute,
                    endsAtMinute: segment.endsAtMinute,
                    order: segment.order,
                  ),
              ],
            ),
        ],
      );
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

bool _notBlank(String? value) => value != null && value.trim().isNotEmpty;
String? _string(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;
int? _int(Object? value) => value is int ? value : int.tryParse('$value');
int _requiredInt(Object? value, String path) =>
    _int(value) ??
    (throw CourseImportException(
      CourseImportErrorCategory.invalidDraft,
      '$path 缺失或无效。',
    ));
String _requiredString(Object? value, String path) =>
    _string(value) ??
    (throw CourseImportException(
      CourseImportErrorCategory.invalidDraft,
      '$path 缺失或无效。',
    ));
Set<int> _intSet(Object? value) =>
    value is List ? value.map(_int).whereType<int>().toSet() : const <int>{};
