import '../domain/course_import_models.dart';

String courseImportSourceLabel(CourseImportSourceType source) =>
    switch (source) {
      CourseImportSourceType.imageOcr => '课程表图片',
      CourseImportSourceType.shareCode ||
      CourseImportSourceType.qrCode => 'Check D 分享',
      CourseImportSourceType.excel => 'Excel 文件',
      CourseImportSourceType.csv => 'CSV 文件',
      CourseImportSourceType.html => 'HTML 网页课表',
      CourseImportSourceType.pdf => 'PDF 课程表',
      _ => '课程导入',
    };

String courseImportIssueLabel(CourseImportIssue issue) {
  if (issue.path.contains('weeks')) return '无法确定该课程的上课周次，请检查。';
  if (issue.path.contains('segments')) return '未找到匹配的作息节次，已使用具体时间。';
  if (issue.path.contains('time')) return '课程时间无法识别，请检查。';
  if (issue.path.contains('weekday')) return '无法确定上课星期，请检查。';
  if (issue.state == CourseImportFieldState.conflict) return '你的课表中可能已经存在相同课程。';
  return issue.message;
}

String courseImportErrorLabel(CourseImportException error) =>
    switch (error.category) {
      CourseImportErrorCategory.pdfImageOnly =>
        '这个 PDF 主要由图片组成，暂时无法直接读取。你可以将课程表保存为图片，然后使用“课程表图片”导入。',
      CourseImportErrorCategory.timetableNotFound =>
        '没有找到课程表，请确认选择的是包含课程安排的文件。',
      CourseImportErrorCategory.htmlMalformed => 'HTML 文件格式不正确，无法读取课程表。',
      CourseImportErrorCategory.pdfTextExtractionFailed =>
        '无法读取 PDF 的文本内容，请尝试其他文件。',
      CourseImportErrorCategory.fileReadFailed => '文件读取失败，请重新选择。',
      CourseImportErrorCategory.invalidTime => '课程时间无法识别，请检查。',
      CourseImportErrorCategory.invalidWeekRule => '无法确定该课程的上课周次，请检查。',
      _ => error.message,
    };
