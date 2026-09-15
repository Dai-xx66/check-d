import 'package:check_d/features/courses/domain/course_import_models.dart';
import 'package:check_d/features/courses/domain/course_share_models.dart';
import 'package:check_d/features/courses/presentation/course_import_copy.dart';
import 'package:check_d/features/courses/presentation/course_share_scanner_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('import sources have user-facing Chinese labels', () {
    expect(courseImportSourceLabel(CourseImportSourceType.imageOcr), '课程表图片');
    expect(
      courseImportSourceLabel(CourseImportSourceType.shareCode),
      'Check D 分享',
    );
    expect(courseImportSourceLabel(CourseImportSourceType.excel), 'Excel 文件');
    expect(courseImportSourceLabel(CourseImportSourceType.csv), 'CSV 文件');
    expect(courseImportSourceLabel(CourseImportSourceType.html), 'HTML 网页课表');
    expect(courseImportSourceLabel(CourseImportSourceType.pdf), 'PDF 课程表');
  });

  test('QR image uses the existing Check D share-code validation', () {
    expect(CourseShareQrDecoder.decode('checkd://share/AB7K4M2Q'), 'AB7K4M2Q');
    expect(
      () => CourseShareQrDecoder.decode('https://example.com/not-check-d'),
      throwsA(isA<CourseShareException>()),
    );
  });

  test('import warnings and image-only PDF errors are localized', () {
    expect(
      courseImportIssueLabel(
        const CourseImportIssue(
          state: CourseImportFieldState.ambiguous,
          path: 'rows[1].weeks',
          message: 'raw',
        ),
      ),
      '无法确定该课程的上课周次，请检查。',
    );
    expect(
      courseImportErrorLabel(
        const CourseImportException(
          CourseImportErrorCategory.pdfImageOnly,
          'raw',
        ),
      ),
      contains('课程表图片'),
    );
  });
}
