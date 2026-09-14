import 'dart:convert';
import 'dart:typed_data';

import 'package:check_d/features/courses/data/course_document_import_adapter.dart';
import 'package:check_d/features/courses/domain/course_import_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const adapter = CourseDocumentImportAdapter();

  CourseImportSource htmlSource(String value, {int? tableIndex}) =>
      CourseImportSource(
        type: CourseImportSourceType.html,
        payload: CourseDocumentFile(
          filename: 'schedule.html',
          bytes: Uint8List.fromList(utf8.encode(value)),
          tableIndex: tableIndex,
        ),
      );

  test('HTML table uses the shared tabular parser', () async {
    final draft = await adapter.parse(
      htmlSource('''
        <table class="timetable"><tr><th>课程名称</th><th>星期</th><th>节次</th><th>周次</th><th>教室</th></tr>
        <tr><td>高等数学&nbsp;</td><td>星期一</td><td>1-2节</td><td>1-18周</td><td>A301</td></tr></table>
      '''),
    );
    expect(draft.sourceType, CourseImportSourceType.html);
    expect(draft.courses.single.title, '高等数学');
    expect(draft.courses.single.scheduleRules.single.weekday, 1);
  });

  test('HTML timetable grid expands rowspan and colspan', () async {
    final draft = await adapter.parse(
      htmlSource('''
        <table id="course-table"><tr><th>节次</th><th>星期一</th><th>星期二</th></tr>
        <tr><td rowspan="2">1-2节</td><td colspan="2">数据库<br>张老师<br>1-16周<br>A201</td></tr>
        <tr></tr></table>
      '''),
    );
    final course = draft.courses.single;
    expect(course.title, '数据库');
    expect(course.scheduleRules.length, 2);
    expect(
      course.scheduleRules.map((rule) => rule.weekday),
      containsAll([1, 2]),
    );
  });

  test('HTML reports no timetable rather than parsing a normal page', () async {
    expect(
      () => adapter.parse(htmlSource('<html><body><h1>欢迎</h1></body></html>')),
      throwsA(
        isA<CourseImportException>().having(
          (error) => error.category,
          'category',
          CourseImportErrorCategory.timetableNotFound,
        ),
      ),
    );
  });

  test('malformed HTML has a clear category', () async {
    expect(
      () => adapter.parse(htmlSource('not html')),
      throwsA(
        isA<CourseImportException>().having(
          (error) => error.category,
          'category',
          CourseImportErrorCategory.htmlMalformed,
        ),
      ),
    );
  });

  test('multiple HTML tables can be inspected and selected', () async {
    const source = '''
      <table class="timetable"><caption>第一张</caption><tr><th>课程名称</th><th>星期</th><th>节次</th></tr><tr><td>数学</td><td>星期一</td><td>1节</td></tr></table>
      <table class="timetable"><caption>第二张</caption><tr><th>课程名称</th><th>星期</th><th>节次</th></tr><tr><td>英语</td><td>星期二</td><td>2节</td></tr></table>
    ''';
    final file = CourseDocumentFile(
      filename: 'schedule.html',
      bytes: Uint8List.fromList(utf8.encode(source)),
    );
    final tables = await adapter.inspectHtml(file);
    expect(tables, hasLength(2));
    final draft = await adapter.parse(
      htmlSource(source, tableIndex: tables.last.index),
    );
    expect(draft.courses.single.title, '英语');
  });

  test('text PDF uses the same tabular course parser', () async {
    final pdfAdapter = CourseDocumentImportAdapter(
      pdfTextExtractor: _FakePdfTextExtractor('''课程名称 | 星期 | 节次 | 周次 | 教室
高等数学 | 星期一 | 1-2节 | 1-18周 | A301
课程名称 | 星期 | 节次 | 周次 | 教室
大学英语 | 星期二 | 3-4节 | 1-18周 | A302'''),
    );
    final draft = await pdfAdapter.parse(
      CourseImportSource(
        type: CourseImportSourceType.pdf,
        payload: CourseDocumentFile(
          filename: 'schedule.pdf',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      ),
    );
    expect(draft.courses.map((course) => course.title), ['高等数学', '大学英语']);
  });

  test('image-only PDF has an explicit safe error', () async {
    final pdfAdapter = CourseDocumentImportAdapter(
      pdfTextExtractor: _FakePdfTextExtractor(''),
    );
    expect(
      () => pdfAdapter.parse(
        CourseImportSource(
          type: CourseImportSourceType.pdf,
          payload: CourseDocumentFile(
            filename: 'scan.pdf',
            bytes: Uint8List.fromList([1]),
          ),
        ),
      ),
      throwsA(
        isA<CourseImportException>().having(
          (error) => error.category,
          'category',
          CourseImportErrorCategory.pdfImageOnly,
        ),
      ),
    );
  });
}

class _FakePdfTextExtractor implements CoursePdfTextExtractor {
  const _FakePdfTextExtractor(this.value);
  final String value;
  @override
  Future<CoursePdfExtractedText> extract(Uint8List bytes) async =>
      CoursePdfExtractedText(text: value, pageCount: 2);
}
