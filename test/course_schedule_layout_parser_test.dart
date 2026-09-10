import 'package:check_d/features/courses/domain/course_models.dart';
import 'package:check_d/features/courses/domain/course_schedule_import_models.dart';
import 'package:check_d/features/courses/domain/course_schedule_layout_parser.dart';
import 'package:check_d/features/courses/domain/local_ocr_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final parser = CourseScheduleLayoutParser();

  test('maps Monday course block and section range into one draft rule', () {
    final result = parser.parse(
      _page([
        _token('周一', 200, 40),
        _token('周二', 400, 40),
        _token('第1节', 30, 180),
        _token('第2节', 30, 280),
        _token('高等数学 1-2节 1-16周 张老师 A101', 200, 210),
      ]),
    );

    expect(result.courses, hasLength(1));
    final course = result.courses.single;
    expect(course.name, '高等数学');
    expect(course.rules.single.weekday, DateTime.monday);
    expect(course.rules.single.recognizedSectionNumbers, [1, 2]);
    expect(course.rules.single.weekRuleType, CourseWeekRuleType.everyWeek);
    expect(course.rules.single.startWeek, 1);
    expect(course.rules.single.endWeek, 16);
  });

  test('keeps non-contiguous sections and parses odd/even/custom weeks', () {
    final odd = parser
        .parse(_page(_gridCourse('离散数学 1,3节 2-16双周')))
        .courses
        .single
        .rules
        .single;
    expect(odd.recognizedSectionNumbers, [1, 3]);
    expect(odd.weekRuleType, CourseWeekRuleType.evenWeeks);
    expect(odd.startWeek, 2);
    expect(odd.endWeek, 16);

    final custom = parser
        .parse(_page(_gridCourse('英语 1节 第1、3、5周')))
        .courses
        .single
        .rules
        .single;
    expect(custom.weekRuleType, CourseWeekRuleType.custom);
    expect(custom.weekNumbers, {1, 3, 5});

    final mixed = parser
        .parse(_page(_gridCourse('算法 1节 1-4,7-10周')))
        .courses
        .single
        .rules
        .single;
    expect(mixed.weekRuleType, CourseWeekRuleType.custom);
    expect(mixed.weekNumbers, {1, 2, 3, 4, 7, 8, 9, 10});
  });

  test(
    'unknown week information remains needs-review instead of every week',
    () {
      final rule = parser
          .parse(_page(_gridCourse('数据库 1节')))
          .courses
          .single
          .rules
          .single;
      expect(rule.weekRuleType, isNull);
      expect(rule.weekRuleConfirmed, isFalse);
      expect(rule.warnings, isNotEmpty);
    },
  );

  test('reports which table axis was not found', () {
    final result = parser.parse(_page([_token('第1节', 30, 180)]));
    expect(result.warnings.single.kind, CourseImportWarningKind.missingWeekday);
  });

  test('same course with matching teacher and room is grouped across days', () {
    final result = parser.parse(
      _page([
        _token('周一', 200, 40),
        _token('周三', 600, 40),
        _token('第1节', 30, 180),
        _token('第2节', 30, 280),
        _token('高数 1节 1-16周 张老师 A101', 200, 180),
        _token('高数 2节 1-16周 张老师 A101', 600, 280),
      ]),
    );
    expect(result.courses, hasLength(1));
    expect(result.courses.single.rules, hasLength(2));
  });

  test('filters schedule metadata, headers, labels and watermarks', () {
    final result = parser.parse(
      _page([
        _token('2026秋季课程表', 400, 90),
        _token('计算机科学与技术1班', 400, 110),
        _token('周一', 200, 40),
        _token('周二', 400, 40),
        _token('第1节', 30, 180),
        _token('第2节', 30, 280),
        _token('教务系统水印', 200, 180),
      ]),
    );
    expect(result.courses, isEmpty);
    expect(result.debug!.rejectedTokens, isNotEmpty);
  });

  test('groups multiple OCR lines in a valid course cell into one draft', () {
    final result = parser.parse(
      _page([
        _token('周一', 200, 40),
        _token('周二', 400, 40),
        _token('第1节', 30, 180),
        _token('第2节', 30, 280),
        _token('高等数学', 200, 180),
        _token('张老师', 200, 190),
        _token('A101', 200, 200),
        _token('1-16周', 200, 210),
      ]),
    );
    expect(result.courses, hasLength(1));
    final course = result.courses.single;
    expect(course.name, '高等数学');
    expect(course.teacher, '张老师');
    expect(course.classroom, 'A101');
    expect(course.rules, hasLength(1));
  });

  test('rejects a course-like token outside the schedule body', () {
    final result = parser.parse(
      _page([
        _token('周一', 200, 40),
        _token('周二', 400, 40),
        _token('第1节', 30, 180),
        _token('第2节', 30, 280),
        _token('高等数学', 650, 700),
      ]),
    );
    expect(result.courses, isEmpty);
    expect(result.debug!.rejectedTokens, hasLength(1));
  });

  test('keeps an uncertain valid cell as needs-review, not every week', () {
    final result = parser.parse(
      _page([
        _token('周一', 200, 40),
        _token('周二', 400, 40),
        _token('第1节', 30, 180),
        _token('第2节', 30, 280),
        _token('数据库原理', 200, 180),
      ]),
    );
    expect(result.courses, hasLength(1));
    final rule = result.courses.single.rules.single;
    expect(rule.weekRuleConfirmed, isFalse);
    expect(rule.warnings, isNotEmpty);
  });
}

List<OcrToken> _gridCourse(String course) => [
  _token('周一', 200, 40),
  _token('第1节', 30, 180),
  _token('第2节', 30, 280),
  _token('第3节', 30, 380),
  _token(course, 200, 220),
];

OcrPageResult _page(List<OcrToken> tokens) =>
    OcrPageResult(imageWidth: 800, imageHeight: 800, tokens: tokens);
OcrToken _token(String text, double x, double y) => OcrToken(
  text: text,
  boundingBox: OcrBoundingBox(
    left: x - 20,
    top: y - 10,
    right: x + 20,
    bottom: y + 10,
  ),
);
