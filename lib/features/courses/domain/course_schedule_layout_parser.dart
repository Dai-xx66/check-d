import 'course_models.dart';
import 'course_schedule_import_models.dart';
import 'local_ocr_models.dart';

/// Converts local OCR text and geometry into editable course drafts. It is
/// deliberately conservative: missing weekday, sections, or week rules remain
/// warnings instead of becoming invented course data.
class CourseScheduleLayoutParser {
  CourseScheduleRecognitionResult parse(OcrPageResult page) {
    final weekdays = _weekdayHeaders(page.tokens);
    final sections = _sectionHeaders(page.tokens, page.imageWidth);
    if (weekdays.isEmpty || sections.isEmpty) {
      return CourseScheduleRecognitionResult(
        courses: const [],
        warnings: [
          if (weekdays.isEmpty)
            const CourseImportWarning(
              CourseImportWarningKind.missingWeekday,
              '未识别到星期标题，请确认图片包含周一至周日。',
            ),
          if (sections.isEmpty)
            const CourseImportWarning(
              CourseImportWarningKind.missingSections,
              '未识别到节次标题，请确认图片包含第1节、第2节等信息。',
            ),
        ],
      );
    }
    final grid = _ScheduleGrid.fromHeaders(
      page: page,
      weekdays: weekdays,
      sections: sections,
    );
    final ignored = {
      ...weekdays.map((item) => item.token),
      ...sections.map((item) => item.token),
    };
    final cells = <_CellKey, List<OcrToken>>{};
    final rejected = <OcrBoundingBox>[];
    for (final token in page.tokens) {
      if (ignored.contains(token) || token.text.trim().isEmpty) continue;
      final day = grid.dayFor(token.boundingBox.centerX);
      final section = grid.sectionFor(token.boundingBox.centerY);
      if (day == null || section == null || _isNonCourseText(token.text)) {
        rejected.add(token.boundingBox);
        continue;
      }
      cells.putIfAbsent(_CellKey(day, section), () => []).add(token);
    }
    final candidates = <_Candidate>[];
    for (final entry in cells.entries) {
      final candidate = _candidate(entry.key, entry.value);
      if (candidate != null) candidates.add(candidate);
    }
    final drafts = _group(candidates);
    return CourseScheduleRecognitionResult(
      courses: drafts,
      detectedSegments: _detectedSegments(page.tokens),
      debug: CourseScheduleParseDebug(
        weekdayColumns: grid.columns.map((item) => item.bounds).toList(),
        sectionRows: grid.rows.map((item) => item.bounds).toList(),
        acceptedCells: [for (final tokens in cells.values) _unionBox(tokens)],
        rejectedTokens: rejected,
      ),
    );
  }

  List<_WeekdayHeader> _weekdayHeaders(List<OcrToken> tokens) {
    final found = <int, _WeekdayHeader>{};
    for (final token in tokens) {
      final day = _weekday(token.text);
      if (day != null &&
          (!found.containsKey(day) ||
              token.boundingBox.centerY <
                  found[day]!.token.boundingBox.centerY))
        found[day] = _WeekdayHeader(day, token);
    }
    return found.values.toList()..sort(
      (a, b) =>
          a.token.boundingBox.centerX.compareTo(b.token.boundingBox.centerX),
    );
  }

  List<_SectionHeader> _sectionHeaders(List<OcrToken> tokens, double width) {
    final found = <int, _SectionHeader>{};
    for (final token in tokens) {
      if (token.boundingBox.centerX > width * .28) continue;
      final match = RegExp(
        r'^(?:第\s*)?(\d{1,2})(?:\s*节)?$',
      ).firstMatch(_compact(token.text));
      final value = match == null ? null : int.tryParse(match.group(1)!);
      if (value != null && value > 0 && !found.containsKey(value))
        found[value] = _SectionHeader(value, token);
    }
    return found.values.toList()..sort(
      (a, b) =>
          a.token.boundingBox.centerY.compareTo(b.token.boundingBox.centerY),
    );
  }

  _Candidate? _candidate(_CellKey key, List<OcrToken> tokens) {
    final text = tokens
        .map((item) => item.text.trim())
        .where((item) => item.isNotEmpty)
        .join(' ');
    final lines = text
        .split(RegExp(r'\s+'))
        .where((item) => item.isNotEmpty)
        .toList();
    final teacher = lines.cast<String?>().firstWhere(
      (item) => item != null && _teacherExpression.hasMatch(item),
      orElse: () => null,
    );
    final classroom = lines.cast<String?>().firstWhere(
      (item) => item != null && _classroomExpression.hasMatch(item),
      orElse: () => null,
    );
    final week = _weekRule(text);
    final sections = _sectionList(text);
    final name = _courseName(lines, teacher: teacher, classroom: classroom);
    if (name.isEmpty) return null;
    return _Candidate(
      name: name,
      teacher: teacher,
      classroom: classroom,
      weekday: key.weekday,
      sections: sections.isEmpty ? [key.section] : sections,
      week: week,
    );
  }

  List<RecognizedCourseDraft> _group(List<_Candidate> candidates) {
    final groups = <String, List<_Candidate>>{};
    for (final item in candidates) {
      // Without corroborating teacher/classroom metadata, same names on
      // different days remain separate rather than being dangerously merged.
      final evidence = '${item.teacher ?? ''}|${item.classroom ?? ''}';
      final key = evidence == '|'
          ? '${item.name}|${item.weekday}'
          : '${item.name}|$evidence';
      groups.putIfAbsent(key, () => []).add(item);
    }
    var id = 0;
    return [
      for (final group in groups.values)
        RecognizedCourseDraft(
          id: 'local-${id++}',
          name: group.first.name,
          teacher: group.first.teacher,
          classroom: group.first.classroom,
          rules: [for (final item in _mergeSameDayCells(group)) _toRule(item)],
        ),
    ];
  }

  RecognizedScheduleRuleDraft _toRule(_Candidate item) {
    final week = item.week;
    return RecognizedScheduleRuleDraft(
      weekday: item.weekday,
      recognizedSectionNumbers: [...item.sections]..sort(),
      weekRuleType: week?.type,
      startWeek: week?.start,
      endWeek: week?.end,
      intervalWeeks: week?.interval,
      weekNumbers: week?.numbers ?? {},
      weekRuleConfirmed: week != null,
      warnings: week == null
          ? const [
              CourseImportWarning(
                CourseImportWarningKind.unconfirmedWeekRule,
                '周次信息请确认',
              ),
            ]
          : const [],
    );
  }

  List<RecognizedScheduleSegmentDraft> _detectedSegments(
    List<OcrToken> tokens,
  ) {
    final result = <RecognizedScheduleSegmentDraft>[];
    final expression = RegExp(
      r'第?\s*(\d{1,2})\s*节?.*?(\d{1,2}:\d{2})\s*[-–~至]\s*(\d{1,2}:\d{2})',
    );
    for (final token in tokens) {
      final match = expression.firstMatch(_compact(token.text));
      if (match == null) continue;
      final number = int.tryParse(match.group(1)!);
      final start = _minute(match.group(2)!);
      final end = _minute(match.group(3)!);
      if (number != null && start != null && end != null && end > start)
        result.add(
          RecognizedScheduleSegmentDraft(
            number: number,
            startsAtMinute: start,
            endsAtMinute: end,
          ),
        );
    }
    return result;
  }

  List<_Candidate> _mergeSameDayCells(List<_Candidate> candidates) {
    final ordered = [...candidates]
      ..sort((a, b) => a.sections.first.compareTo(b.sections.first));
    final merged = <_Candidate>[];
    for (final item in ordered) {
      final previous = merged.isEmpty ? null : merged.last;
      if (previous == null ||
          previous.weekday != item.weekday ||
          previous.name != item.name ||
          previous.teacher != item.teacher ||
          previous.classroom != item.classroom ||
          !_sameWeek(previous.week, item.week) ||
          !_sectionsAreAdjacent(previous.sections, item.sections)) {
        merged.add(item);
        continue;
      }
      merged[merged.length - 1] = _Candidate(
        name: previous.name,
        teacher: previous.teacher,
        classroom: previous.classroom,
        weekday: previous.weekday,
        sections: {...previous.sections, ...item.sections}.toList(),
        week: previous.week,
      );
    }
    return merged;
  }

  bool _sameWeek(_WeekRule? a, _WeekRule? b) =>
      a?.type == b?.type &&
      a?.start == b?.start &&
      a?.end == b?.end &&
      a?.interval == b?.interval &&
      _sameSet(a?.numbers ?? const {}, b?.numbers ?? const {});

  bool _sectionsAreAdjacent(List<int> first, List<int> second) =>
      first.reduce((a, b) => a > b ? a : b) + 1 >=
      second.reduce((a, b) => a < b ? a : b);

  bool _sameSet(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);

  String _courseName(
    List<String> lines, {
    required String? teacher,
    required String? classroom,
  }) {
    for (final line in lines) {
      if (line == teacher || line == classroom || _isNonCourseText(line)) {
        continue;
      }
      final clean = line
          .replaceAll(_teacherExpression, '')
          .replaceAll(_classroomExpression, '')
          .replaceAll(_weekExpression, '')
          .replaceAll(_sectionExpression, '')
          .replaceAll(_timeExpression, '')
          .trim();
      if (_looksLikeCourseName(clean)) return clean;
    }
    return '';
  }

  bool _looksLikeCourseName(String value) {
    final compact = _compact(value);
    if (compact.length < 2 || _isNonCourseText(compact)) return false;
    return RegExp(r'[\u4e00-\u9fff]{2,}|[A-Za-z]{3,}').hasMatch(compact);
  }

  bool _isNonCourseText(String value) {
    final compact = _compact(value);
    if (compact.isEmpty || _weekday(compact) != null) return true;
    if (RegExp(r'^(?:第?\d{1,2}节?|上午|下午|晚上|午休|备注)$').hasMatch(compact)) {
      return true;
    }
    return RegExp(
      r'(?:课程表|学期|年级|班级|专业|学院|姓名|学号|教务|打印|制表|水印|页脚|仅供|课表说明)',
    ).hasMatch(compact);
  }

  OcrBoundingBox _unionBox(List<OcrToken> tokens) => OcrBoundingBox(
    left: tokens.map((item) => item.boundingBox.left).reduce(_min),
    top: tokens.map((item) => item.boundingBox.top).reduce(_min),
    right: tokens.map((item) => item.boundingBox.right).reduce(_max),
    bottom: tokens.map((item) => item.boundingBox.bottom).reduce(_max),
  );

  double _min(double a, double b) => a < b ? a : b;
  double _max(double a, double b) => a > b ? a : b;

  int? _weekday(String text) {
    final normalized = _compact(text).toLowerCase();
    const names = {
      '周一': 1,
      '星期一': 1,
      'mon': 1,
      'monday': 1,
      '周二': 2,
      '星期二': 2,
      'tue': 2,
      'tuesday': 2,
      '周三': 3,
      '星期三': 3,
      'wed': 3,
      'wednesday': 3,
      '周四': 4,
      '星期四': 4,
      'thu': 4,
      'thursday': 4,
      '周五': 5,
      '星期五': 5,
      'fri': 5,
      'friday': 5,
      '周六': 6,
      '星期六': 6,
      'sat': 6,
      'saturday': 6,
      '周日': 7,
      '周天': 7,
      '星期日': 7,
      'sun': 7,
      'sunday': 7,
    };
    return names[normalized];
  }

  List<int> _sectionList(String text) {
    final compact = _compact(text);
    // A trailing "节" or leading "第" distinguishes a period range from
    // week text such as "2-16双周".
    final range = RegExp(
      r'(?:第(\d{1,2})[\-–~至](\d{1,2})|(\d{1,2})[\-–~至](\d{1,2})节)',
    ).firstMatch(compact);
    if (range != null) {
      final a = int.parse(range.group(1) ?? range.group(3)!);
      final b = int.parse(range.group(2) ?? range.group(4)!);
      return [for (var value = a; value <= b; value++) value];
    }
    final list = RegExp(r'第?((?:\d{1,2}[,、，]?)+)节').firstMatch(compact);
    if (list == null) return const [];
    return RegExp(r'\d{1,2}')
        .allMatches(list.group(1)!)
        .map((match) => int.parse(match.group(0)!))
        .toList();
  }

  _WeekRule? _weekRule(String text) {
    final compact = _compact(text);
    final everyN = RegExp(r'(?:每|隔)(\d{1,2})周').firstMatch(compact);
    if (everyN != null) {
      final interval = int.parse(everyN.group(1)!);
      if (interval > 1) {
        return _WeekRule(CourseWeekRuleType.everyNWeeks, interval: interval);
      }
    }
    final ranges = RegExp(
      r'(\d{1,2})[\-–~至](\d{1,2})(单|双)?周',
    ).allMatches(compact).toList();
    final hasCompositeRangeList = RegExp(
      r'\d{1,2}[\-–~至]\d{1,2}\s*[,、，]',
    ).hasMatch(compact);
    final range = ranges.length == 1 && !hasCompositeRangeList
        ? ranges.single
        : null;
    if (range != null)
      return _WeekRule(
        range.group(3) == '单'
            ? CourseWeekRuleType.oddWeeks
            : range.group(3) == '双'
            ? CourseWeekRuleType.evenWeeks
            : CourseWeekRuleType.everyWeek,
        start: int.parse(range.group(1)!),
        end: int.parse(range.group(2)!),
      );
    if (compact.contains('单周'))
      return const _WeekRule(CourseWeekRuleType.oddWeeks);
    if (compact.contains('双周'))
      return const _WeekRule(CourseWeekRuleType.evenWeeks);
    if (compact.contains('周')) {
      final values = <int>{};
      for (final match in RegExp(
        r'(\d{1,2})[\-–~至](\d{1,2})',
      ).allMatches(compact)) {
        final start = int.parse(match.group(1)!);
        final end = int.parse(match.group(2)!);
        if (end >= start) {
          values.addAll([for (var value = start; value <= end; value++) value]);
        }
      }
      final remainder = compact.replaceAll(
        RegExp(r'\d{1,2}[\-–~至]\d{1,2}'),
        '',
      );
      values.addAll(
        RegExp(
          r'\d{1,2}',
        ).allMatches(remainder).map((match) => int.parse(match.group(0)!)),
      );
      if (values.isNotEmpty)
        return _WeekRule(CourseWeekRuleType.custom, numbers: values);
    }
    return null;
  }

  int? _minute(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    return hour == null || minute == null ? null : hour * 60 + minute;
  }

  String _compact(String value) => value.replaceAll(RegExp(r'\s+'), '');
}

final _teacherExpression = RegExp(r'[\u4e00-\u9fff]{1,8}(?:老师|教师|教授|讲师)');
final _classroomExpression = RegExp(r'(?:教学楼)?[A-Za-z]\d{2,4}|\d{3,4}教');
final _weekExpression = RegExp(
  r'(?:第?\d{1,2}(?:[\-–~至、，,]\d{1,2})*(?:单|双)?周|[单双]周|每\d{1,2}周)',
);
final _sectionExpression = RegExp(r'(?:第?\d{1,2}(?:[\-–~至、，,]\d{1,2})*节)');
final _timeExpression = RegExp(r'\d{1,2}:\d{2}(?:[\-–~至]\d{1,2}:\d{2})?');

class _WeekdayHeader {
  const _WeekdayHeader(this.day, this.token);
  final int day;
  final OcrToken token;
}

class _SectionHeader {
  const _SectionHeader(this.number, this.token);
  final int number;
  final OcrToken token;
}

class _ScheduleGrid {
  const _ScheduleGrid({required this.columns, required this.rows});

  final List<_GridColumn> columns;
  final List<_GridRow> rows;

  factory _ScheduleGrid.fromHeaders({
    required OcrPageResult page,
    required List<_WeekdayHeader> weekdays,
    required List<_SectionHeader> sections,
  }) {
    final columnCenters = weekdays
        .map((item) => item.token.boundingBox.centerX)
        .toList();
    final rowCenters = sections
        .map((item) => item.token.boundingBox.centerY)
        .toList();
    final top = weekdays
        .map((item) => item.token.boundingBox.bottom)
        .reduce((a, b) => a > b ? a : b);
    return _ScheduleGrid(
      columns: [
        for (var index = 0; index < weekdays.length; index++)
          _GridColumn(
            weekdays[index].day,
            _axisBounds(
              centers: columnCenters,
              index: index,
              minimum: 0,
              maximum: page.imageWidth,
            ),
            imageHeight: page.imageHeight,
          ),
      ],
      rows: [
        for (var index = 0; index < sections.length; index++)
          _GridRow(
            sections[index].number,
            _axisBounds(
              centers: rowCenters,
              index: index,
              minimum: top,
              maximum: page.imageHeight,
            ),
            imageWidth: page.imageWidth,
          ),
      ],
    );
  }

  int? dayFor(double x) {
    for (final column in columns) {
      if (x >= column.bounds.left && x <= column.bounds.right) {
        return column.day;
      }
    }
    return null;
  }

  int? sectionFor(double y) {
    for (final row in rows) {
      if (y >= row.bounds.top && y <= row.bounds.bottom) {
        return row.section;
      }
    }
    return null;
  }

  static OcrBoundingBox _axisBounds({
    required List<double> centers,
    required int index,
    required double minimum,
    required double maximum,
  }) {
    final current = centers[index];
    final before = index == 0
        ? current - _fallbackHalfWidth(centers, maximum - minimum)
        : (centers[index - 1] + current) / 2;
    final after = index == centers.length - 1
        ? current + _fallbackHalfWidth(centers, maximum - minimum)
        : (current + centers[index + 1]) / 2;
    return OcrBoundingBox(
      left: before.clamp(minimum, maximum),
      top: before.clamp(minimum, maximum),
      right: after.clamp(minimum, maximum),
      bottom: after.clamp(minimum, maximum),
    );
  }

  static double _fallbackHalfWidth(List<double> centers, double extent) {
    if (centers.length > 1) {
      return (centers[1] - centers[0]).abs() / 2;
    }
    return extent * .08;
  }
}

class _GridColumn {
  _GridColumn(this.day, OcrBoundingBox bounds, {required double imageHeight})
    : bounds = OcrBoundingBox(
        left: bounds.left,
        top: 0,
        right: bounds.right,
        bottom: imageHeight,
      );

  final int day;
  final OcrBoundingBox bounds;
}

class _GridRow {
  _GridRow(this.section, OcrBoundingBox bounds, {required double imageWidth})
    : bounds = OcrBoundingBox(
        left: 0,
        top: bounds.top,
        right: imageWidth,
        bottom: bounds.bottom,
      );

  final int section;
  final OcrBoundingBox bounds;
}

class _CellKey {
  const _CellKey(this.weekday, this.section);
  final int weekday;
  final int section;
  @override
  bool operator ==(Object other) =>
      other is _CellKey && other.weekday == weekday && other.section == section;
  @override
  int get hashCode => Object.hash(weekday, section);
}

class _Candidate {
  const _Candidate({
    required this.name,
    required this.teacher,
    required this.classroom,
    required this.weekday,
    required this.sections,
    required this.week,
  });
  final String name;
  final String? teacher;
  final String? classroom;
  final int weekday;
  final List<int> sections;
  final _WeekRule? week;
}

class _WeekRule {
  const _WeekRule(
    this.type, {
    this.start,
    this.end,
    this.interval,
    this.numbers = const {},
  });
  final CourseWeekRuleType type;
  final int? start;
  final int? end;
  final int? interval;
  final Set<int> numbers;
}
