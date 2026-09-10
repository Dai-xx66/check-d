import 'dart:typed_data';

import '../domain/course_schedule_import_models.dart';
import '../domain/course_schedule_layout_parser.dart';
import 'course_schedule_recognizer.dart';
import 'local_ocr_engine.dart';

/// The default recognizer for supported native platforms. It deliberately has
/// no cloud fallback: local recognition must remain private and predictable.
class LocalCourseScheduleRecognizer implements CourseScheduleRecognizer {
  LocalCourseScheduleRecognizer({
    LocalOcrEngine? engine,
    CourseScheduleLayoutParser? parser,
  }) : _engine = engine ?? PlatformLocalOcrEngine(),
       _parser = parser ?? CourseScheduleLayoutParser();

  final LocalOcrEngine _engine;
  final CourseScheduleLayoutParser _parser;

  @override
  Future<CourseScheduleRecognitionResult> recognize({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    if (mimeType != 'image/png' && mimeType != 'image/jpeg') {
      throw const CourseScheduleRecognitionUnavailable(
        '仅支持 PNG、JPG、JPEG 课程表图片。',
      );
    }
    try {
      final page = await _engine.recognize(bytes);
      if (page.tokens.isEmpty) {
        throw const CourseScheduleRecognitionUnavailable(
          '本地 OCR 未识别到文字，请更换清晰完整的图片。',
        );
      }
      final result = _parser.parse(page);
      if (result.courses.isEmpty) {
        final explanation = result.warnings.isEmpty
            ? '未识别到课程表结构，请确认图片包含星期、节次和课程内容。'
            : result.warnings.first.message;
        throw CourseScheduleRecognitionUnavailable(explanation);
      }
      return result;
    } on LocalOcrUnavailable catch (error) {
      throw CourseScheduleRecognitionUnavailable(error.message);
    }
  }
}
