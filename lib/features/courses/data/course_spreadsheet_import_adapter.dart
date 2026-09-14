import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as excel;

import '../domain/course_import_models.dart';
import '../domain/course_models.dart';

/// Limits apply before any worksheet is expanded so a malformed upload cannot
/// make the local-only import screen consume unbounded memory.
class CourseSpreadsheetImportConfig {
  const CourseSpreadsheetImportConfig({
    this.maxFileBytes = 4 * 1024 * 1024,
    this.maxRows = 1000,
    this.maxCourses = 100,
  });

  final int maxFileBytes;
  final int maxRows;
  final int maxCourses;
}

class CourseSpreadsheetFile {
  const CourseSpreadsheetFile({
    required this.bytes,
    required this.filename,
    this.sheetName,
  });

  final Uint8List bytes;
  final String filename;
  final String? sheetName;

  String get extension => filename.split('.').last.toLowerCase();

  CourseSpreadsheetFile copyWith({String? sheetName}) => CourseSpreadsheetFile(
    bytes: bytes,
    filename: filename,
    sheetName: sheetName ?? this.sheetName,
  );
}

class CourseSpreadsheetSheet {
  const CourseSpreadsheetSheet({
    required this.name,
    required this.rowCount,
    required this.hasContent,
  });

  final String name;
  final int rowCount;
  final bool hasContent;
}

enum _SpreadsheetColumn {
  title,
  teacher,
  weekday,
  sections,
  startsAt,
  endsAt,
  weeks,
  classroom,
  note,
}

class CourseSpreadsheetImportAdapter implements CourseImportAdapter {
  const CourseSpreadsheetImportAdapter({
    this.config = const CourseSpreadsheetImportConfig(),
  });

  final CourseSpreadsheetImportConfig config;

  /// Kept in one place so supporting a new campus export is a data addition,
  /// not a set of parser conditionals.
  static const Map<_SpreadsheetColumn, Set<String>> _headerAliases = {
    _SpreadsheetColumn.title: {'课程', '课程名称', '课程名', '科目'},
    _SpreadsheetColumn.teacher: {'教师', '任课教师', '老师'},
    _SpreadsheetColumn.weekday: {'星期', '周几', '上课星期'},
    _SpreadsheetColumn.sections: {'节次', '上课节次', '课节'},
    _SpreadsheetColumn.startsAt: {'开始时间', '上课时间'},
    _SpreadsheetColumn.endsAt: {'结束时间', '下课时间'},
    _SpreadsheetColumn.weeks: {'周次', '教学周', '上课周次'},
    _SpreadsheetColumn.classroom: {'教室', '地点', '上课地点'},
    _SpreadsheetColumn.note: {'备注', '说明'},
  };

  @override
  Set<CourseImportSourceType> get supportedSources => const {
    CourseImportSourceType.excel,
    CourseImportSourceType.csv,
  };

  @override
  bool supports(CourseImportSource source) =>
      supportedSources.contains(source.type);

  Future<List<CourseSpreadsheetSheet>> inspect(
    CourseSpreadsheetFile file,
  ) async {
    _validateFile(file);
    if (file.extension == 'csv') {
      final rows = _decodeCsv(file.bytes);
      return [
        CourseSpreadsheetSheet(
          name: 'CSV',
          rowCount: rows.length,
          hasContent: rows.any(_hasContent),
        ),
      ];
    }
    final workbook = _decodeWorkbook(file.bytes);
    final sheets = [
      for (final entry in workbook.tables.entries)
        CourseSpreadsheetSheet(
          name: entry.key,
          rowCount: entry.value.rows.length,
          hasContent: entry.value.rows.any(
            (row) => row.any((cell) => _excelCellText(cell).isNotEmpty),
          ),
        ),
    ];
    if (sheets.isEmpty || !sheets.any((sheet) => sheet.hasContent)) {
      throw const CourseImportException(
        CourseImportErrorCategory.emptyWorkbook,
        '工作簿中没有可读取的内容。',
      );
    }
    return sheets;
  }

  @override
  Future<CourseImportDraft> parse(CourseImportSource source) async {
    if (!supports(source) || source.payload is! CourseSpreadsheetFile) {
      throw const CourseImportException(
        CourseImportErrorCategory.unsupportedFormat,
        '表格导入源格式无效。',
      );
    }
    final file = source.payload as CourseSpreadsheetFile;
    _validateFile(file);
    final rows = _rowsFor(file);
    if (rows.length > config.maxRows) {
      throw CourseImportException(
        CourseImportErrorCategory.sourceLimitExceeded,
        '文件共有 ${rows.length} 行，最多支持 ${config.maxRows} 行。',
      );
    }
    if (!rows.any(_hasContent)) {
      throw const CourseImportException(
        CourseImportErrorCategory.emptyWorkbook,
        '文件中没有可读取的课程内容。',
      );
    }
    return _draftFromRows(rows, source.type);
  }

  /// Shared tabular normalization for other local-only file adapters. HTML
  /// and text-PDF imports intentionally use the same header, week, time, and
  /// segment parsing rules as Excel/CSV instead of maintaining a second set.
  CourseImportDraft parseTabularRows({
    required List<List<String>> rows,
    required CourseImportSourceType sourceType,
  }) {
    if (rows.length > config.maxRows) {
      throw CourseImportException(
        CourseImportErrorCategory.sourceLimitExceeded,
        '表格共有 ${rows.length} 行，最多支持 ${config.maxRows} 行。',
      );
    }
    return _draftFromRows(rows, sourceType);
  }

  List<List<String>> _rowsFor(CourseSpreadsheetFile file) {
    if (file.extension == 'csv') return _decodeCsv(file.bytes);
    final workbook = _decodeWorkbook(file.bytes);
    final candidates = workbook.tables.entries
        .where(
          (entry) => entry.value.rows.any(
            (row) => row.any((cell) => _excelCellText(cell).isNotEmpty),
          ),
        )
        .toList();
    if (candidates.isEmpty) {
      throw const CourseImportException(
        CourseImportErrorCategory.emptyWorkbook,
        '工作簿中没有可读取的内容。',
      );
    }
    final selected = file.sheetName == null
        ? (candidates.length == 1 ? candidates.single : null)
        : candidates.where((entry) => entry.key == file.sheetName).firstOrNull;
    if (selected == null) {
      throw const CourseImportException(
        CourseImportErrorCategory.sheetNotFound,
        '请先选择要导入的工作表。',
      );
    }
    return [
      for (final row in selected.value.rows)
        [for (final cell in row) _excelCellText(cell)],
    ];
  }

  excel.Excel _decodeWorkbook(Uint8List bytes) {
    try {
      return excel.Excel.decodeBytes(bytes);
    } catch (_) {
      throw const CourseImportException(
        CourseImportErrorCategory.fileReadFailed,
        '无法读取 Excel 文件，请确认文件未损坏且为 .xlsx 格式。',
      );
    }
  }

  List<List<String>> _decodeCsv(Uint8List bytes) {
    try {
      var content = utf8.decode(bytes, allowMalformed: false);
      if (content.startsWith('\ufeff')) content = content.substring(1);
      return [
        for (final row in csv.decode(content))
          [for (final cell in row) cell?.toString().trim() ?? ''],
      ];
    } on FormatException {
      throw const CourseImportException(
        CourseImportErrorCategory.fileReadFailed,
        'CSV 必须使用 UTF-8 编码。',
      );
    } catch (_) {
      throw const CourseImportException(
        CourseImportErrorCategory.fileReadFailed,
        '无法读取 CSV 文件。',
      );
    }
  }

  CourseImportDraft _draftFromRows(
    List<List<String>> rows,
    CourseImportSourceType sourceType,
  ) {
    final headerIndex = rows.indexWhere(_looksLikeHeader);
    if (headerIndex < 0) {
      throw const CourseImportException(
        CourseImportErrorCategory.headerNotRecognized,
        '无法识别表头。请使用包含课程名、星期和节次或时间的表格。',
      );
    }
    final columns = _mapHeaders(rows[headerIndex]);
    if (!_isUsableHeader(columns)) {
      throw const CourseImportException(
        CourseImportErrorCategory.headerNotRecognized,
        '表头缺少课程名、星期或节次/时间，暂时不能安全导入。',
      );
    }
    final issues = <CourseImportIssue>[];
    final courses = <String, _CourseAccumulator>{};
    for (var index = headerIndex + 1; index < rows.length; index++) {
      final row = rows[index];
      if (!_hasContent(row)) continue;
      final line = index + 1;
      final title = _cell(row, columns[_SpreadsheetColumn.title]).trim();
      if (title.isEmpty) {
        issues.add(
          CourseImportIssue(
            state: CourseImportFieldState.sourceWarning,
            path: 'rows[$line]',
            message: '第 $line 行缺少课程名，已跳过。',
          ),
        );
        continue;
      }
      final teacher = _optional(
        _cell(row, columns[_SpreadsheetColumn.teacher]),
      );
      final classroom = _optional(
        _cell(row, columns[_SpreadsheetColumn.classroom]),
      );
      final note = _optional(_cell(row, columns[_SpreadsheetColumn.note]));
      final rules = _parseRules(
        line: line,
        weekdayText: _cell(row, columns[_SpreadsheetColumn.weekday]),
        sectionsText: _cell(row, columns[_SpreadsheetColumn.sections]),
        startsAtText: _cell(row, columns[_SpreadsheetColumn.startsAt]),
        endsAtText: _cell(row, columns[_SpreadsheetColumn.endsAt]),
        weeksText: _cell(row, columns[_SpreadsheetColumn.weeks]),
        classroom: classroom,
      );
      final key = _mergeKey(title, teacher);
      final existing = courses[key];
      if (existing == null) {
        courses[key] = _CourseAccumulator(
          importKey: 'spreadsheet-$line-$key',
          title: title,
          teacher: teacher,
          classroom: classroom,
          note: note,
          colorValue: _colorFor(title),
          rules: rules,
        );
      } else {
        existing.rules.addAll(rules);
        existing.mergeMetadata(classroom: classroom, note: note);
      }
    }
    if (courses.isEmpty) {
      throw const CourseImportException(
        CourseImportErrorCategory.noCourseFound,
        '没有找到可导入的课程行。',
      );
    }
    if (courses.length > config.maxCourses) {
      throw CourseImportException(
        CourseImportErrorCategory.sourceLimitExceeded,
        '识别到 ${courses.length} 门课程，最多支持 ${config.maxCourses} 门。',
      );
    }
    return CourseImportDraft(
      schemaVersion: CourseImportDraft.currentSchemaVersion,
      sourceType: sourceType,
      issues: issues,
      courses: [for (final course in courses.values) course.toDraft()],
    );
  }

  List<CourseImportScheduleRuleDraft> _parseRules({
    required int line,
    required String weekdayText,
    required String sectionsText,
    required String startsAtText,
    required String endsAtText,
    required String weeksText,
    required String? classroom,
  }) {
    final weekdays = _splitSchedules(weekdayText);
    final sections = _splitSchedules(sectionsText);
    final starts = _splitSchedules(startsAtText);
    final ends = _splitSchedules(endsAtText);
    final count = [
      weekdays.length,
      sections.length,
      starts.length,
      ends.length,
    ].fold(1, (largest, value) => value > largest ? value : largest);
    return [
      for (var index = 0; index < count; index++)
        _parseRule(
          line: line,
          weekdayText: _at(weekdays, index),
          sectionsText: _at(sections, index),
          startsAtText: _at(starts, index),
          endsAtText: _at(ends, index),
          weeksText: weeksText,
          classroom: classroom,
        ),
    ];
  }

  CourseImportScheduleRuleDraft _parseRule({
    required int line,
    required String weekdayText,
    required String sectionsText,
    required String startsAtText,
    required String endsAtText,
    required String weeksText,
    required String? classroom,
  }) {
    final issues = <CourseImportIssue>[];
    final weekday = _parseWeekday(weekdayText);
    if (weekday == null) {
      issues.add(
        CourseImportIssue(
          state: CourseImportFieldState.invalid,
          path: 'rows[$line].weekday',
          message: '第 $line 行的星期无法识别，请在预览中确认。',
        ),
      );
    }
    final sectionNumbers = _parseSections('$weekdayText $sectionsText');
    final range = _parseTimeRange(startsAtText, endsAtText);
    if ((startsAtText.isNotEmpty || endsAtText.isNotEmpty) && range == null) {
      issues.add(
        CourseImportIssue(
          state: CourseImportFieldState.invalid,
          path: 'rows[$line].time',
          message: '第 $line 行的时间无法识别，请使用 08:00-09:40 格式。',
        ),
      );
    }
    if (sectionNumbers.isEmpty && range == null) {
      issues.add(
        CourseImportIssue(
          state: CourseImportFieldState.missing,
          path: 'rows[$line].schedule',
          message: '第 $line 行缺少节次或真实时间。',
        ),
      );
    }
    final week = _parseWeeks(weeksText);
    if (week.issue != null) {
      issues.add(
        CourseImportIssue(
          state: CourseImportFieldState.invalid,
          path: 'rows[$line].weeks',
          message: '第 $line 行${week.issue}',
        ),
      );
    }
    return CourseImportScheduleRuleDraft(
      weekday: weekday,
      startsAtMinute: range?.$1,
      endsAtMinute: range?.$2,
      weekRuleType: week.type,
      startWeek: week.startWeek,
      endWeek: week.endWeek,
      intervalWeeks: week.intervalWeeks,
      customWeeks: week.customWeeks,
      // Exact clock times take priority over inferred local period numbers.
      timeMode: range == null && sectionNumbers.isNotEmpty
          ? CourseScheduleTimeMode.periods
          : CourseScheduleTimeMode.customTime,
      segments: range == null
          ? [
              for (final number in sectionNumbers)
                CourseImportSegmentCandidate(
                  label: '第$number节',
                  order: number - 1,
                ),
            ]
          : const [],
      classroomOverride: classroom,
      issues: issues,
    );
  }

  Map<_SpreadsheetColumn, int> _mapHeaders(List<String> row) {
    final result = <_SpreadsheetColumn, int>{};
    for (var index = 0; index < row.length; index++) {
      final header = _normalizeHeader(row[index]);
      for (final entry in _headerAliases.entries) {
        if (entry.value.map(_normalizeHeader).contains(header)) {
          result.putIfAbsent(entry.key, () => index);
        }
      }
    }
    return result;
  }

  bool _looksLikeHeader(List<String> row) => _isUsableHeader(_mapHeaders(row));
  bool _isUsableHeader(Map<_SpreadsheetColumn, int> columns) =>
      columns.containsKey(_SpreadsheetColumn.title) &&
      columns.containsKey(_SpreadsheetColumn.weekday) &&
      (columns.containsKey(_SpreadsheetColumn.sections) ||
          columns.containsKey(_SpreadsheetColumn.startsAt));

  void _validateFile(CourseSpreadsheetFile file) {
    if (file.extension != 'xlsx' && file.extension != 'csv') {
      throw const CourseImportException(
        CourseImportErrorCategory.unsupportedFileType,
        '仅支持 .xlsx 与 .csv 课程文件。',
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

  static String _excelCellText(excel.Data? cell) {
    final value = cell?.value;
    return switch (value) {
      excel.TimeCellValue() =>
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}',
      excel.DateTimeCellValue() =>
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}',
      _ => value?.toString().trim() ?? '',
    };
  }

  static bool _hasContent(List<String> row) =>
      row.any((cell) => cell.trim().isNotEmpty);
  static String _cell(List<String> row, int? index) =>
      index == null || index >= row.length ? '' : row[index];
  static String? _optional(String value) =>
      value.trim().isEmpty ? null : value.trim();
  static String _mergeKey(String title, String? teacher) =>
      '${_normalizeHeader(title)}|${_normalizeHeader(teacher ?? '')}';
  static String _normalizeHeader(String value) => value
      .replaceFirst('\ufeff', '')
      .replaceAll(RegExp(r'[\s_\-—–:：()（）\[\]【】]'), '')
      .trim()
      .toLowerCase();
  static List<String> _splitSchedules(String value) => value
      .split(RegExp(r'[;；\n]+'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  static String _at(List<String> values, int index) => values.isEmpty
      ? ''
      : values.length == 1
      ? values.single
      : index < values.length
      ? values[index]
      : '';

  static int? _parseWeekday(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const chinese = {
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '日': 7,
      '天': 7,
    };
    final chineseMatch = RegExp(r'(?:星期|周)([一二三四五六日天])').firstMatch(normalized);
    if (chineseMatch != null) {
      return chinese[chineseMatch.group(1)];
    }
    if (normalized.length == 1) {
      return chinese[normalized];
    }
    if (normalized.contains('monday') ||
        RegExp(r'\bmon\b').hasMatch(normalized)) {
      return 1;
    }
    if (normalized.contains('tuesday') ||
        RegExp(r'\btue\b').hasMatch(normalized)) {
      return 2;
    }
    if (normalized.contains('wednesday') ||
        RegExp(r'\bwed\b').hasMatch(normalized)) {
      return 3;
    }
    if (normalized.contains('thursday') ||
        RegExp(r'\bthu\b').hasMatch(normalized)) {
      return 4;
    }
    if (normalized.contains('friday') ||
        RegExp(r'\bfri\b').hasMatch(normalized)) {
      return 5;
    }
    if (normalized.contains('saturday') ||
        RegExp(r'\bsat\b').hasMatch(normalized)) {
      return 6;
    }
    if (normalized.contains('sunday') ||
        RegExp(r'\bsun\b').hasMatch(normalized)) {
      return 7;
    }
    return null;
  }

  static List<int> _parseSections(String value) {
    final match = RegExp(
      r'(\d+)\s*(?:[-~—–至]\s*(\d+))?\s*节?',
    ).firstMatch(value);
    if (match == null) return const [];
    final first = int.tryParse(match.group(1)!);
    final last = int.tryParse(match.group(2) ?? match.group(1)!);
    if (first == null ||
        last == null ||
        first <= 0 ||
        last < first ||
        last - first > 20) {
      return const [];
    }
    return [for (var value = first; value <= last; value++) value];
  }

  static (int, int)? _parseTimeRange(String startsAt, String endsAt) {
    final times = [..._timeMatches(startsAt), ..._timeMatches(endsAt)];
    if (times.length < 2) return null;
    final start = times[0];
    final end = times[1];
    return start < end ? (start, end) : null;
  }

  static List<int> _timeMatches(String value) =>
      RegExp(r'(?<!\d)(\d{1,2}):(\d{2})(?!\d)')
          .allMatches(value)
          .map((match) {
            final hour = int.parse(match.group(1)!);
            final minute = int.parse(match.group(2)!);
            return hour >= 0 && hour <= 23 && minute <= 59
                ? hour * 60 + minute
                : -1;
          })
          .where((minute) => minute >= 0)
          .toList();

  static _WeekParse _parseWeeks(String value) {
    final normalized = value
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('（', '(')
        .replaceAll('）', ')');
    if (normalized.isEmpty) return const _WeekParse();
    final range = RegExp(
      r'(?:第)?(\d+)\s*[-~—–至]\s*(\d+)周?',
    ).firstMatch(normalized);
    final start = range == null ? null : int.tryParse(range.group(1)!);
    final end = range == null ? null : int.tryParse(range.group(2)!);
    if (range != null &&
        (start == null || end == null || start <= 0 || end < start)) {
      return const _WeekParse(issue: '的周次范围无效。');
    }
    if (normalized.contains('单')) {
      return _WeekParse(
        type: CourseWeekRuleType.oddWeeks,
        startWeek: start,
        endWeek: end,
      );
    }
    if (normalized.contains('双')) {
      return _WeekParse(
        type: CourseWeekRuleType.evenWeeks,
        startWeek: start,
        endWeek: end,
      );
    }
    final everyN = RegExp(r'每(\d+)周').firstMatch(normalized);
    if (everyN != null) {
      final interval = int.tryParse(everyN.group(1)!);
      if (interval == null || interval <= 1) {
        return const _WeekParse(issue: '的每 N 周规则无效。');
      }
      return _WeekParse(
        type: CourseWeekRuleType.everyNWeeks,
        startWeek: start,
        endWeek: end,
        intervalWeeks: interval,
      );
    }
    if (range != null || normalized == '每周') {
      return _WeekParse(
        type: CourseWeekRuleType.everyWeek,
        startWeek: start,
        endWeek: end,
      );
    }
    final numbers = RegExp(
      r'\d+',
    ).allMatches(normalized).map((match) => int.parse(match.group(0)!)).toSet();
    if (numbers.isNotEmpty && RegExp(r'^[第\d,，、周]+$').hasMatch(normalized)) {
      return _WeekParse(type: CourseWeekRuleType.custom, customWeeks: numbers);
    }
    return const _WeekParse(issue: '的周次无法识别，请在预览中确认。');
  }

  static int _colorFor(String name) {
    const colors = [0xFF8FA7F5, 0xFFD0A4F5, 0xFF7DCFB6, 0xFFFFB36B, 0xFFF28BA8];
    return colors[name.codeUnits.fold<int>(0, (sum, value) => sum + value) %
        colors.length];
  }
}

class _WeekParse {
  const _WeekParse({
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

class _CourseAccumulator {
  _CourseAccumulator({
    required this.importKey,
    required this.title,
    required this.teacher,
    required this.classroom,
    required this.note,
    required this.colorValue,
    required this.rules,
  });

  final String importKey;
  final String title;
  final String? teacher;
  String? classroom;
  String? note;
  final int colorValue;
  final List<CourseImportScheduleRuleDraft> rules;

  void mergeMetadata({String? classroom, String? note}) {
    this.classroom ??= classroom;
    this.note ??= note;
  }

  CourseImportCourseDraft toDraft() => CourseImportCourseDraft(
    importKey: importKey,
    title: title,
    teacher: teacher,
    classroom: classroom,
    note: note,
    colorValue: colorValue,
    scheduleRules: rules,
  );
}
