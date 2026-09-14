// The parser has several compact guard clauses; braces would obscure the
// table-expansion flow without changing its safety properties.
// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../domain/course_import_models.dart';
import '../domain/course_models.dart';
import 'course_spreadsheet_import_adapter.dart';

/// One set of limits for locally parsed timetable documents. Source bytes are
/// only held long enough to build an import draft; they are never persisted.
class CourseDocumentImportConfig {
  const CourseDocumentImportConfig({
    this.maxFileBytes = 4 * 1024 * 1024,
    this.maxPdfPages = 20,
    this.maxTextCharacters = 200000,
    this.maxCourses = 100,
  });

  final int maxFileBytes;
  final int maxPdfPages;
  final int maxTextCharacters;
  final int maxCourses;
}

class CourseDocumentFile {
  const CourseDocumentFile({
    required this.bytes,
    required this.filename,
    this.tableIndex,
  });

  final Uint8List bytes;
  final String filename;
  final int? tableIndex;

  String get extension => filename.split('.').last.toLowerCase();

  CourseDocumentFile copyWith({int? tableIndex}) => CourseDocumentFile(
    bytes: bytes,
    filename: filename,
    tableIndex: tableIndex ?? this.tableIndex,
  );
}

class CourseDocumentTableCandidate {
  const CourseDocumentTableCandidate({
    required this.index,
    required this.score,
    required this.label,
  });

  final int index;
  final int score;
  final String label;
}

class CoursePdfExtractedText {
  const CoursePdfExtractedText({required this.text, required this.pageCount});

  final String text;
  final int pageCount;
}

abstract interface class CoursePdfTextExtractor {
  Future<CoursePdfExtractedText> extract(Uint8List bytes);
}

class LocalCoursePdfTextExtractor implements CoursePdfTextExtractor {
  const LocalCoursePdfTextExtractor();

  @override
  Future<CoursePdfExtractedText> extract(Uint8List bytes) async {
    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: bytes);
      return CoursePdfExtractedText(
        text: PdfTextExtractor(document).extractText(layoutText: true),
        pageCount: document.pages.count,
      );
    } finally {
      document?.dispose();
    }
  }
}

/// Converts saved timetable HTML and text-based PDFs into the Stage 13A draft
/// pipeline. It has no network or persistence dependency.
class CourseDocumentImportAdapter implements CourseImportAdapter {
  const CourseDocumentImportAdapter({
    this.config = const CourseDocumentImportConfig(),
    this.pdfTextExtractor = const LocalCoursePdfTextExtractor(),
    this.tabularAdapter = const CourseSpreadsheetImportAdapter(),
  });

  final CourseDocumentImportConfig config;
  final CoursePdfTextExtractor pdfTextExtractor;
  final CourseSpreadsheetImportAdapter tabularAdapter;

  @override
  Set<CourseImportSourceType> get supportedSources => const {
    CourseImportSourceType.html,
    CourseImportSourceType.pdf,
  };

  @override
  bool supports(CourseImportSource source) =>
      supportedSources.contains(source.type);

  Future<List<CourseDocumentTableCandidate>> inspectHtml(
    CourseDocumentFile file,
  ) async {
    _validate(file, CourseImportSourceType.html);
    final document = _htmlDocument(file.bytes);
    final candidates = <CourseDocumentTableCandidate>[];
    final tables = document.querySelectorAll('table');
    for (var index = 0; index < tables.length; index++) {
      final rows = _expandHtmlTable(tables[index]);
      final score = _tableScore(rows, tables[index]);
      if (score <= 0) continue;
      final caption = _clean(tables[index].querySelector('caption')?.text);
      candidates.add(
        CourseDocumentTableCandidate(
          index: index,
          score: score,
          label: caption ?? '课程表 ${candidates.length + 1}',
        ),
      );
    }
    if (candidates.isEmpty) {
      throw const CourseImportException(
        CourseImportErrorCategory.timetableNotFound,
        '没有找到可识别的课程表。请保存包含课程表格的网页后再导入。',
      );
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates;
  }

  @override
  Future<CourseImportDraft> parse(CourseImportSource source) async {
    if (!supports(source) || source.payload is! CourseDocumentFile) {
      throw const CourseImportException(
        CourseImportErrorCategory.unsupportedFormat,
        '课程文档导入源格式无效。',
      );
    }
    final file = source.payload as CourseDocumentFile;
    _validate(file, source.type);
    return switch (source.type) {
      CourseImportSourceType.html => _parseHtml(file),
      CourseImportSourceType.pdf => _parsePdf(file),
      _ => throw const CourseImportException(
        CourseImportErrorCategory.unsupportedFormat,
        '暂不支持该课程文档格式。',
      ),
    };
  }

  Future<CourseImportDraft> _parseHtml(CourseDocumentFile file) async {
    final document = _htmlDocument(file.bytes);
    final candidates = await inspectHtml(file);
    final selected = file.tableIndex == null
        ? candidates.first
        : candidates
              .where((candidate) => candidate.index == file.tableIndex)
              .firstOrNull;
    if (selected == null) {
      throw const CourseImportException(
        CourseImportErrorCategory.timetableNotFound,
        '请选择要导入的课程表。',
      );
    }
    final table = document.querySelectorAll('table')[selected.index];
    return _parseRowsOrGrid(
      _expandHtmlTable(table),
      CourseImportSourceType.html,
    );
  }

  Future<CourseImportDraft> _parsePdf(CourseDocumentFile file) async {
    CoursePdfExtractedText extracted;
    try {
      extracted = await pdfTextExtractor.extract(file.bytes);
    } on CourseImportException {
      rethrow;
    } catch (_) {
      throw const CourseImportException(
        CourseImportErrorCategory.pdfTextExtractionFailed,
        '无法提取 PDF 文本。请确认文件未损坏且不是受保护的 PDF。',
      );
    }
    if (extracted.pageCount > config.maxPdfPages) {
      throw CourseImportException(
        CourseImportErrorCategory.sourceLimitExceeded,
        'PDF 共 ${extracted.pageCount} 页，最多支持 ${config.maxPdfPages} 页。',
      );
    }
    final text = _normalizeText(extracted.text);
    if (text.isEmpty) {
      throw const CourseImportException(
        CourseImportErrorCategory.pdfImageOnly,
        'PDF 主要是图片，当前只能解析可复制文本的 PDF。请导出图片后使用课程表图片识别。',
      );
    }
    if (text.length > config.maxTextCharacters) {
      throw CourseImportException(
        CourseImportErrorCategory.sourceLimitExceeded,
        'PDF 文本过长，最多支持 ${config.maxTextCharacters} 个字符。',
      );
    }
    final rows = _pdfRows(text);
    return _parseRowsOrGrid(rows, CourseImportSourceType.pdf);
  }

  CourseImportDraft _parseRowsOrGrid(
    List<List<String>> rows,
    CourseImportSourceType sourceType,
  ) {
    try {
      final draft = tabularAdapter.parseTabularRows(
        rows: rows,
        sourceType: sourceType,
      );
      return _enforceCourseLimit(draft);
    } on CourseImportException catch (error) {
      if (error.category != CourseImportErrorCategory.headerNotRecognized) {
        rethrow;
      }
      return _parseWeekdayGrid(rows, sourceType);
    }
  }

  CourseImportDraft _parseWeekdayGrid(
    List<List<String>> rows,
    CourseImportSourceType sourceType,
  ) {
    final headerIndex = rows.indexWhere(
      (row) => row.where((cell) => _weekday(cell) != null).length >= 2,
    );
    if (headerIndex < 0) {
      throw const CourseImportException(
        CourseImportErrorCategory.timetableNotFound,
        '没有找到课程表的星期列。请使用带有星期和节次/时间的课程表。',
      );
    }
    final header = rows[headerIndex];
    final courses = <String, _DocumentCourseAccumulator>{};
    final issues = <CourseImportIssue>[];
    for (var rowIndex = headerIndex + 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      if (row.isEmpty || !row.any((value) => _clean(value) != null)) continue;
      final rowLabel = row.firstOrNull ?? '';
      final sections = _sections(rowLabel);
      final range = _range(rowLabel);
      for (
        var column = 1;
        column < row.length && column < header.length;
        column++
      ) {
        final weekday = _weekday(header[column]);
        final cell = _clean(row[column]);
        if (weekday == null || cell == null) continue;
        final parsed = _courseFromCell(
          cell,
          weekday: weekday,
          sections: sections,
          range: range,
          line: rowIndex + 1,
        );
        if (parsed == null) continue;
        final key = '${_key(parsed.title)}|${_key(parsed.teacher ?? '')}';
        final accumulator = courses.putIfAbsent(
          key,
          () => _DocumentCourseAccumulator(parsed),
        );
        if (!identical(accumulator.initial, parsed)) accumulator.add(parsed);
      }
    }
    if (courses.isEmpty) {
      throw const CourseImportException(
        CourseImportErrorCategory.noCourseFound,
        '没有从课程表中找到可导入的课程。',
      );
    }
    final draft = CourseImportDraft(
      schemaVersion: CourseImportDraft.currentSchemaVersion,
      sourceType: sourceType,
      courses: [for (final course in courses.values) course.toDraft()],
      issues: issues,
    );
    return _enforceCourseLimit(draft);
  }

  _DocumentParsedCourse? _courseFromCell(
    String text, {
    required int weekday,
    required List<int> sections,
    required (int, int)? range,
    required int line,
  }) {
    final lines = text
        .split(RegExp(r'[\n\r;；]+'))
        .map(_clean)
        .whereType<String>()
        .toList();
    if (lines.isEmpty) return null;
    String? teacher;
    String? classroom;
    String? weeks;
    String? title;
    for (final value in lines) {
      if (weeks == null && _weekText(value)) {
        weeks = value;
        continue;
      }
      if (teacher == null && RegExp(r'(老师|教师|教授|讲师)').hasMatch(value)) {
        teacher = value.replaceFirst(RegExp(r'^(老师|教师)[:：]?'), '').trim();
        continue;
      }
      if (classroom == null && _looksLikeClassroom(value)) {
        classroom = value;
        continue;
      }
      title ??= value;
    }
    if (title == null) return null;
    final ruleIssues = <CourseImportIssue>[];
    if (sections.isEmpty && range == null) {
      ruleIssues.add(
        CourseImportIssue(
          state: CourseImportFieldState.missing,
          path: 'grid[$line].schedule',
          message: '第 $line 行缺少节次或时间，请在预览中补充。',
        ),
      );
    }
    final parsedWeek = _week(weeks ?? '');
    if (parsedWeek.issue != null || weeks == null) {
      ruleIssues.add(
        CourseImportIssue(
          state: weeks == null
              ? CourseImportFieldState.ambiguous
              : CourseImportFieldState.invalid,
          path: 'grid[$line].weeks',
          message: weeks == null
              ? '第 $line 行未找到周次，请在预览中确认。'
              : '第 $line 行${parsedWeek.issue}',
        ),
      );
    }
    return _DocumentParsedCourse(
      title: title,
      teacher: teacher,
      classroom: classroom,
      colorValue: _color(title),
      rule: CourseImportScheduleRuleDraft(
        weekday: weekday,
        startsAtMinute: range?.$1,
        endsAtMinute: range?.$2,
        weekRuleType: parsedWeek.type,
        startWeek: parsedWeek.startWeek,
        endWeek: parsedWeek.endWeek,
        intervalWeeks: parsedWeek.intervalWeeks,
        customWeeks: parsedWeek.customWeeks,
        timeMode: range == null && sections.isNotEmpty
            ? CourseScheduleTimeMode.periods
            : CourseScheduleTimeMode.customTime,
        segments: range == null
            ? [
                for (final section in sections)
                  CourseImportSegmentCandidate(
                    label: '第$section节',
                    order: section - 1,
                  ),
              ]
            : const [],
        classroomOverride: classroom,
        issues: ruleIssues,
      ),
    );
  }

  CourseImportDraft _enforceCourseLimit(CourseImportDraft draft) {
    if (draft.courses.length > config.maxCourses) {
      throw CourseImportException(
        CourseImportErrorCategory.sourceLimitExceeded,
        '识别到 ${draft.courses.length} 门课程，最多支持 ${config.maxCourses} 门。',
      );
    }
    return draft;
  }

  dom.Document _htmlDocument(Uint8List bytes) {
    final source = _decodeHtml(bytes);
    if (!source.contains('<')) {
      throw const CourseImportException(
        CourseImportErrorCategory.htmlMalformed,
        'HTML 文件格式不正确，无法读取课程表。',
      );
    }
    final document = html.parse(source);
    for (final element in document.querySelectorAll(
      'script, style, noscript, template, [hidden], [aria-hidden="true"]',
    )) {
      element.remove();
    }
    for (final element in document.querySelectorAll('[style]')) {
      final style = element.attributes['style']
          ?.replaceAll(' ', '')
          .toLowerCase();
      if (style?.contains('display:none') == true ||
          style?.contains('visibility:hidden') == true) {
        element.remove();
      }
    }
    for (final lineBreak in document.querySelectorAll('br')) {
      lineBreak.replaceWith(dom.Text('\n'));
    }
    return document;
  }

  String _decodeHtml(Uint8List bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const CourseImportException(
        CourseImportErrorCategory.fileReadFailed,
        'HTML 文件必须使用 UTF-8 编码。',
      );
    }
  }

  List<List<String>> _expandHtmlTable(dom.Element table) {
    final active = <int, _TableSpan>{};
    final result = <List<String>>[];
    for (final tr in table.querySelectorAll('tr')) {
      final row = <String>[];
      var column = 0;
      void consumeActive() {
        while (active.containsKey(column)) {
          final span = active[column]!;
          _put(row, column, span.text);
          span.remainingRows--;
          if (span.remainingRows == 0) active.remove(column);
          column++;
        }
      }

      consumeActive();
      for (final cell in tr.children.where(
        (element) => element.localName == 'td' || element.localName == 'th',
      )) {
        consumeActive();
        final text = _normalizeText(cell.text);
        final colspan = int.tryParse(cell.attributes['colspan'] ?? '') ?? 1;
        final rowspan = int.tryParse(cell.attributes['rowspan'] ?? '') ?? 1;
        for (var offset = 0; offset < colspan; offset++) {
          _put(row, column + offset, text);
          if (rowspan > 1) {
            active[column + offset] = _TableSpan(text, rowspan - 1);
          }
        }
        column += colspan;
      }
      while (active.keys.any((index) => index >= column)) {
        consumeActive();
      }
      if (row.isNotEmpty) result.add(row);
    }
    return result;
  }

  int _tableScore(List<List<String>> rows, dom.Element table) {
    final flattened = rows.expand((row) => row).join(' ');
    final weekdayCount = rows
        .map((row) => row.where((cell) => _weekday(cell) != null).length)
        .fold(0, (max, count) => count > max ? count : max);
    final metadata = '${table.id} ${table.classes.join(' ')}'.toLowerCase();
    var score = weekdayCount * 10;
    if (RegExp(r'课程|课表|timetable|schedule|calendar').hasMatch(metadata))
      score += 8;
    if (RegExp(r'课程|节次|时间|周次|星期').hasMatch(flattened)) score += 4;
    return score;
  }

  List<List<String>> _pdfRows(String text) {
    final lines = text
        .split('\n')
        .map(_normalizeText)
        .where((line) => line.isNotEmpty)
        .toList();
    final headerLine = lines.indexWhere(
      (line) => RegExp(r'课程.{0,12}(星期|周几).{0,12}(节次|时间)').hasMatch(line),
    );
    if (headerLine >= 0) {
      final delimiter = lines[headerLine].contains('|')
          ? RegExp(r'\s*\|\s*')
          : RegExp(r'\s{2,}');
      return [
        // Page headers are commonly repeated by campus PDF exports. Keeping
        // only the first one prevents it from becoming a phantom course row.
        for (var index = 0; index < lines.length; index++)
          if (index == headerLine || lines[index] != lines[headerLine])
            lines[index].split(delimiter).map(_normalizeText).toList(),
      ];
    }
    // PDF text extraction preserves page order. Treat blank-free lines as a
    // one-column grid so the structured parser can report ambiguity instead
    // of inventing course data from a visually positioned PDF.
    return [
      for (final line in lines) [line],
    ];
  }

  void _validate(CourseDocumentFile file, CourseImportSourceType type) {
    final supported = switch (type) {
      CourseImportSourceType.html =>
        file.extension == 'html' || file.extension == 'htm',
      CourseImportSourceType.pdf => file.extension == 'pdf',
      _ => false,
    };
    if (!supported) {
      throw const CourseImportException(
        CourseImportErrorCategory.unsupportedFileType,
        '仅支持 .html、.htm 与文本型 .pdf 课程文件。',
      );
    }
    if (file.bytes.isEmpty) {
      throw const CourseImportException(
        CourseImportErrorCategory.fileReadFailed,
        '所选文件为空或无法读取。',
      );
    }
    if (file.bytes.length > config.maxFileBytes) {
      throw CourseImportException(
        CourseImportErrorCategory.sourceLimitExceeded,
        '文件超过 ${config.maxFileBytes ~/ (1024 * 1024)} MB 限制。',
      );
    }
  }

  static void _put(List<String> values, int index, String value) {
    while (values.length <= index) values.add('');
    values[index] = value;
  }

  static String _normalizeText(String value) => value
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .trim();
  static String? _clean(String? value) {
    final normalized = value == null ? '' : _normalizeText(value);
    return normalized.isEmpty ? null : normalized;
  }

  static String _key(String value) =>
      value.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  static int? _weekday(String value) {
    final matched = RegExp(
      r'(?:星期|周)([一二三四五六日天])',
    ).firstMatch(value.replaceAll(RegExp(r'\s+'), ''));
    const map = {
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '日': 7,
      '天': 7,
    };
    return matched == null ? null : map[matched.group(1)];
  }

  static List<int> _sections(String value) {
    final match = RegExp(
      r'(\d+)\s*(?:[-~—–至]\s*(\d+))?\s*节?',
    ).firstMatch(value);
    final first = int.tryParse(match?.group(1) ?? '');
    final last = int.tryParse(match?.group(2) ?? match?.group(1) ?? '');
    if (first == null ||
        last == null ||
        first <= 0 ||
        last < first ||
        last - first > 20)
      return const [];
    return [for (var number = first; number <= last; number++) number];
  }

  static (int, int)? _range(String value) {
    final minutes = RegExp(r'(?<!\d)(\d{1,2}):(\d{2})(?!\d)')
        .allMatches(value)
        .map((match) {
          final hour = int.parse(match.group(1)!);
          final minute = int.parse(match.group(2)!);
          return hour <= 23 && minute <= 59 ? hour * 60 + minute : -1;
        })
        .where((value) => value >= 0)
        .toList();
    return minutes.length >= 2 && minutes[0] < minutes[1]
        ? (minutes[0], minutes[1])
        : null;
  }

  static bool _weekText(String value) =>
      RegExp(r'(周|单周|双周|每\d+周)').hasMatch(value);
  static _DocumentWeek _week(String value) {
    final normalized = value
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('（', '(')
        .replaceAll('）', ')');
    final range = RegExp(
      r'(?:第)?(\d+)\s*[-~—–至]\s*(\d+)周?',
    ).firstMatch(normalized);
    final start = int.tryParse(range?.group(1) ?? '');
    final end = int.tryParse(range?.group(2) ?? '');
    if (range != null &&
        (start == null || end == null || start <= 0 || end < start))
      return const _DocumentWeek(issue: '的周次范围无效。');
    if (normalized.contains('单'))
      return _DocumentWeek(
        type: CourseWeekRuleType.oddWeeks,
        startWeek: start,
        endWeek: end,
      );
    if (normalized.contains('双'))
      return _DocumentWeek(
        type: CourseWeekRuleType.evenWeeks,
        startWeek: start,
        endWeek: end,
      );
    final interval = int.tryParse(
      RegExp(r'每(\d+)周').firstMatch(normalized)?.group(1) ?? '',
    );
    if (interval != null)
      return interval > 1
          ? _DocumentWeek(
              type: CourseWeekRuleType.everyNWeeks,
              startWeek: start,
              endWeek: end,
              intervalWeeks: interval,
            )
          : const _DocumentWeek(issue: '的每 N 周规则无效。');
    if (range != null || normalized == '每周')
      return _DocumentWeek(
        type: CourseWeekRuleType.everyWeek,
        startWeek: start,
        endWeek: end,
      );
    final custom = RegExp(
      r'\d+',
    ).allMatches(normalized).map((match) => int.parse(match.group(0)!)).toSet();
    if (custom.isNotEmpty && RegExp(r'^[第\d,，、周]+$').hasMatch(normalized))
      return _DocumentWeek(
        type: CourseWeekRuleType.custom,
        customWeeks: custom,
      );
    return const _DocumentWeek(issue: '的周次无法识别，请在预览中确认。');
  }

  static bool _looksLikeClassroom(String value) =>
      RegExp(r'(教室|楼|[A-Za-z]{1,4}-?\d{2,4})').hasMatch(value);
  static int _color(String name) {
    const colors = [0xFF8FA7F5, 0xFFD0A4F5, 0xFF7DCFB6, 0xFFFFB36B, 0xFFF28BA8];
    return colors[name.codeUnits.fold<int>(0, (sum, value) => sum + value) %
        colors.length];
  }
}

class _TableSpan {
  _TableSpan(this.text, this.remainingRows);
  final String text;
  int remainingRows;
}

class _DocumentWeek {
  const _DocumentWeek({
    this.type,
    this.startWeek,
    this.endWeek,
    this.intervalWeeks,
    this.customWeeks = const {},
    this.issue,
  });
  final CourseWeekRuleType? type;
  final int? startWeek;
  final int? endWeek;
  final int? intervalWeeks;
  final Set<int> customWeeks;
  final String? issue;
}

class _DocumentParsedCourse {
  const _DocumentParsedCourse({
    required this.title,
    required this.teacher,
    required this.classroom,
    required this.colorValue,
    required this.rule,
  });
  final String title;
  final String? teacher;
  final String? classroom;
  final int colorValue;
  final CourseImportScheduleRuleDraft rule;
}

class _DocumentCourseAccumulator {
  _DocumentCourseAccumulator(this.initial) : rules = [initial.rule];
  final _DocumentParsedCourse initial;
  final List<CourseImportScheduleRuleDraft> rules;
  void add(_DocumentParsedCourse course) {
    if (!rules.any(
      (rule) =>
          rule.weekday == course.rule.weekday &&
          rule.startsAtMinute == course.rule.startsAtMinute &&
          rule.endsAtMinute == course.rule.endsAtMinute &&
          rule.segments.map((item) => item.label).join() ==
              course.rule.segments.map((item) => item.label).join(),
    ))
      rules.add(course.rule);
  }

  CourseImportCourseDraft toDraft() => CourseImportCourseDraft(
    importKey: 'document-${initial.title}-${initial.teacher ?? ''}',
    title: initial.title,
    teacher: initial.teacher,
    classroom: initial.classroom,
    colorValue: initial.colorValue,
    scheduleRules: rules,
  );
}
