import '../domain/course_import_models.dart';
import '../domain/course_share_schema.dart';

class SharePackageImportAdapter implements CourseImportAdapter {
  const SharePackageImportAdapter();

  @override
  Set<CourseImportSourceType> get supportedSources => const {
    CourseImportSourceType.shareCode,
    CourseImportSourceType.qrCode,
  };

  @override
  bool supports(CourseImportSource source) =>
      supportedSources.contains(source.type);

  @override
  Future<CourseImportDraft> parse(CourseImportSource source) async {
    try {
      final package = switch (source.payload) {
        SharePackage package => package,
        String encoded => SharePackage.decode(encoded),
        _ => throw const CourseImportException(
          CourseImportErrorCategory.parseFailed,
          '分享内容格式无效。',
        ),
      };
      final draft = package.toImportDraft();
      return CourseImportDraft(
        schemaVersion: draft.schemaVersion,
        sourceType: source.type,
        semester: draft.semester,
        courses: draft.courses,
        issues: draft.issues,
      );
    } on CourseImportException {
      rethrow;
    } catch (_) {
      throw const CourseImportException(
        CourseImportErrorCategory.parseFailed,
        '无法解析课程分享内容。',
      );
    }
  }
}
