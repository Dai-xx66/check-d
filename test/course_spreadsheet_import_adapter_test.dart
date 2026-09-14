import 'dart:convert';
import 'dart:typed_data';

import 'package:check_d/features/courses/data/course_spreadsheet_import_adapter.dart';
import 'package:check_d/features/courses/domain/course_import_models.dart';
import 'package:check_d/features/courses/domain/course_models.dart';
import 'package:excel/excel.dart' as excel;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const adapter = CourseSpreadsheetImportAdapter();

  CourseImportSource csvSource(String content) => CourseImportSource(
    type: CourseImportSourceType.csv,
    payload: CourseSpreadsheetFile(
      bytes: Uint8List.fromList(utf8.encode(content)),
      filename: '课程.csv',
    ),
  );

  group('CourseSpreadsheetImportAdapter CSV', () {
    test('parses UTF-8 Chinese aliases, time ranges and week ranges', () async {
      final draft = await adapter.parse(
        csvSource(
          '\ufeff课程名称,任课教师,上课星期,开始时间,下课时间,教学周,上课地点\n'
          '高等数学,李老师,周一,08:00,09:40,第1-18周,A203',
        ),
      );

      final course = draft.courses.single;
      final rule = course.scheduleRules.single;
      expect(course.title, '高等数学');
      expect(course.teacher, '李老师');
      expect(course.classroom, 'A203');
      expect(rule.weekday, DateTime.monday);
      expect(rule.startsAtMinute, 480);
      expect(rule.endsAtMinute, 580);
      expect(rule.weekRuleType, CourseWeekRuleType.everyWeek);
      expect(rule.startWeek, 1);
      expect(rule.endWeek, 18);
      expect(rule.timeMode, CourseScheduleTimeMode.customTime);
    });

    test('supports weekday variants and odd even custom week rules', () async {
      final draft = await adapter.parse(
        csvSource(
          '科目,星期,节次,周次\n'
          '英语,Monday,1-2节,1-8周(单)\n'
          '物理,二,3-4节,1-8周（双）\n'
          '化学,Mon,5-6节,1、3、5、7周',
        ),
      );
      final first = draft.courses[0].scheduleRules.single;
      final second = draft.courses[1].scheduleRules.single;
      final third = draft.courses[2].scheduleRules.single;
      expect(first.weekday, DateTime.monday);
      expect(first.weekRuleType, CourseWeekRuleType.oddWeeks);
      expect(second.weekday, DateTime.tuesday);
      expect(second.weekRuleType, CourseWeekRuleType.evenWeeks);
      expect(third.weekRuleType, CourseWeekRuleType.custom);
      expect(third.customWeeks, {1, 3, 5, 7});
      expect(first.segments.map((item) => item.order), [0, 1]);
    });

    test(
      'merges repeated high-confidence course rows into schedule rules',
      () async {
        final draft = await adapter.parse(
          csvSource(
            '课程,教师,星期,节次,周次\n'
            '高等数学,李老师,周一,1-2节,1-18周\n'
            '高等数学,李老师,周三,3-4节,1-18周',
          ),
        );
        expect(draft.courses, hasLength(1));
        expect(draft.courses.single.scheduleRules, hasLength(2));
        expect(draft.courses.single.scheduleRules.map((rule) => rule.weekday), [
          DateTime.monday,
          DateTime.wednesday,
        ]);
      },
    );

    test(
      'keeps quoted commas and ignores blank or malformed rows safely',
      () async {
        final draft = await adapter.parse(
          csvSource(
            '课程名,星期,开始时间,结束时间,备注\n'
            '\n'
            ',周一,08:00,09:40,缺标题\n'
            '数据结构,周二,08:00,09:40,"含,逗号"',
          ),
        );
        expect(draft.courses, hasLength(1));
        expect(draft.courses.single.note, '含,逗号');
        expect(draft.issues.single.message, contains('缺少课程名'));
      },
    );

    test('rejects unrecognized headers instead of guessing columns', () {
      expect(
        () => adapter.parse(csvSource('A,B,C\n数学,一,1-2')),
        throwsA(
          isA<CourseImportException>().having(
            (error) => error.category,
            'category',
            CourseImportErrorCategory.headerNotRecognized,
          ),
        ),
      );
    });

    test('marks invalid time and week values for preview correction', () async {
      final draft = await adapter.parse(
        csvSource('课程,星期,开始时间,结束时间,周次\n数学,周一,25:00,08:00,若干周'),
      );
      final issues = draft.courses.single.scheduleRules.single.issues;
      expect(issues.map((issue) => issue.path), contains('rows[2].time'));
      expect(issues.map((issue) => issue.path), contains('rows[2].weeks'));
      expect(draft.canConfirm, isFalse);
    });

    test('enforces file and row limits before a draft is created', () async {
      const tight = CourseSpreadsheetImportAdapter(
        config: CourseSpreadsheetImportConfig(maxFileBytes: 8, maxRows: 1),
      );
      await expectLater(
        tight.parse(csvSource('课程,星期,节次\n数学,周一,1节')),
        throwsA(
          isA<CourseImportException>().having(
            (error) => error.category,
            'category',
            CourseImportErrorCategory.sourceLimitExceeded,
          ),
        ),
      );
    });
  });

  group('CourseSpreadsheetImportAdapter Excel', () {
    test(
      'selects an explicit non-empty sheet and parses standard xlsx',
      () async {
        final workbook = excel.Excel.createExcel();
        final first = workbook['课程表'];
        first.appendRow([
          excel.TextCellValue('课程'),
          excel.TextCellValue('周几'),
          excel.TextCellValue('课节'),
          excel.TextCellValue('周次'),
        ]);
        first.appendRow([
          excel.TextCellValue('算法'),
          excel.TextCellValue('星期三'),
          excel.TextCellValue('1-2节'),
          excel.TextCellValue('1-16周'),
        ]);
        final second = workbook['说明'];
        second.appendRow([excel.TextCellValue('说明')]);
        final bytes = Uint8List.fromList(workbook.encode()!);
        final input = CourseSpreadsheetFile(bytes: bytes, filename: '课表.xlsx');

        final sheets = await adapter.inspect(input);
        expect(sheets.map((sheet) => sheet.name), containsAll(['课程表', '说明']));
        await expectLater(
          adapter.parse(
            CourseImportSource(
              type: CourseImportSourceType.excel,
              payload: input,
            ),
          ),
          throwsA(
            isA<CourseImportException>().having(
              (error) => error.category,
              'category',
              CourseImportErrorCategory.sheetNotFound,
            ),
          ),
        );

        final draft = await adapter.parse(
          CourseImportSource(
            type: CourseImportSourceType.excel,
            payload: input.copyWith(sheetName: '课程表'),
          ),
        );
        expect(draft.courses.single.title, '算法');
        expect(
          draft.courses.single.scheduleRules.single.weekday,
          DateTime.wednesday,
        );
      },
    );
  });
}
