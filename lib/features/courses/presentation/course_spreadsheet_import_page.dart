import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/course_providers.dart';
import '../data/course_spreadsheet_import_adapter.dart';
import '../domain/course_import_models.dart';
import '../domain/course_models.dart';
import 'semester_settings_page.dart';

class CourseSpreadsheetImportPage extends ConsumerStatefulWidget {
  const CourseSpreadsheetImportPage({super.key});

  @override
  ConsumerState<CourseSpreadsheetImportPage> createState() =>
      _CourseSpreadsheetImportPageState();
}

class _CourseSpreadsheetImportPageState
    extends ConsumerState<CourseSpreadsheetImportPage> {
  PlatformFile? _file;
  List<CourseSpreadsheetSheet> _sheets = const [];
  String? _sheetName;
  String? _semesterId;
  CourseImportDraft? _draft;
  List<CourseImportConflict> _conflicts = const [];
  bool _loading = false;
  bool _confirming = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final semesters =
        ref.watch(semestersProvider).value ?? const <SemesterDetails>[];
    final templates =
        ref.watch(scheduleTemplatesProvider).value ??
        const <ScheduleTemplateDetails>[];
    _semesterId ??= semesters.where((item) => item.isCurrent).firstOrNull?.id;
    final semester = semesters
        .where((item) => item.id == _semesterId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('导入 Excel / CSV 课程')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        children: [
          Text(
            '课程文件只在本机解析。识别结果会先进入可修改的草稿，确认后才写入课程。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            initialValue: _semesterId,
            decoration: const InputDecoration(labelText: '目标学期 *'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('请选择学期'),
              ),
              for (final item in semesters)
                DropdownMenuItem(
                  value: item.id,
                  child: Text(item.isCurrent ? '${item.name}（当前）' : item.name),
                ),
            ],
            onChanged: _loading
                ? null
                : (value) => setState(() {
                    _semesterId = value;
                    _draft = null;
                    _conflicts = const [];
                  }),
          ),
          if (semesters.isEmpty)
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SemesterSettingsPage()),
              ),
              icon: const Icon(Icons.school_outlined),
              label: const Text('先创建学期'),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loading ? null : _pickFile,
            icon: const Icon(Icons.table_view_outlined),
            label: Text(_file == null ? '选择 Excel 或 CSV 文件' : _file!.name),
          ),
          const SizedBox(height: 8),
          Text(
            '支持 .xlsx、UTF-8 CSV；最大 4 MB、1,000 行、100 门课程。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_sheets.length > 1) ...[
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _sheetName,
              decoration: const InputDecoration(labelText: '工作表 *'),
              items: [
                for (final sheet in _sheets.where((item) => item.hasContent))
                  DropdownMenuItem(
                    value: sheet.name,
                    child: Text('${sheet.name}（${sheet.rowCount} 行）'),
                  ),
              ],
              onChanged: _loading
                  ? null
                  : (value) => setState(() {
                      _sheetName = value;
                      _draft = null;
                      _conflicts = const [];
                    }),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _loading || _file == null || semester == null
                ? null
                : () => _prepare(semester, templates),
            icon: _loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.preview_outlined),
            label: Text(_loading ? '正在读取…' : '读取并预览课程'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            _SpreadsheetNotice(
              icon: Icons.error_outline_rounded,
              text: _error!,
            ),
          ],
          if (_draft case final draft?) ...[
            const SizedBox(height: 24),
            Text('检查课程', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              '来源：${_file!.name} · ${draft.courses.length} 门课程 · '
              '${_warningCount(draft)} 个提示 · ${_conflicts.length} 个冲突',
            ),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => _selectAll(true),
                  child: const Text('全选'),
                ),
                TextButton(
                  onPressed: () => _selectAll(false),
                  child: const Text('全不选'),
                ),
              ],
            ),
            for (var index = 0; index < draft.courses.length; index++)
              _SpreadsheetCourseDraftCard(
                course: draft.courses[index],
                onSelected: (selected) => _replaceCourse(
                  index,
                  draft.courses[index].copyWith(selected: selected),
                ),
                onEditCourse: () => _editCourse(index, draft.courses[index]),
                onEditRule: (ruleIndex) =>
                    _editRule(index, ruleIndex, draft.courses[index]),
              ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _confirming || !draft.canConfirm || semester == null
                  ? null
                  : () => _confirm(semester, templates),
              icon: _confirming
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_confirming ? '正在导入…' : '确认导入所选课程'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'csv'],
        withData: true,
      );
      final file = picked?.files.singleOrNull;
      if (file == null) return;
      if (file.bytes == null) {
        setState(() => _error = '无法读取所选文件，请重新选择。');
        return;
      }
      final input = CourseSpreadsheetFile(
        bytes: file.bytes!,
        filename: file.name,
      );
      final sheets = await ref
          .read(courseSpreadsheetImportAdapterProvider)
          .inspect(input);
      if (!mounted) return;
      setState(() {
        _file = file;
        _sheets = sheets;
        _sheetName = sheets.where((item) => item.hasContent).firstOrNull?.name;
        _draft = null;
        _conflicts = const [];
        _error = null;
      });
    } on CourseImportException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _error = '无法打开文件选择器：${error.message ?? '请检查文件访问权限。'}');
      }
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取课程文件，请稍后重试。');
    }
  }

  Future<void> _prepare(
    SemesterDetails semester,
    List<ScheduleTemplateDetails> templates,
  ) async {
    final file = _file;
    if (file?.bytes == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _draft = null;
      _conflicts = const [];
    });
    try {
      final input = CourseSpreadsheetFile(
        bytes: file!.bytes!,
        filename: file.name,
        sheetName: _sheetName,
      );
      final type = input.extension == 'csv'
          ? CourseImportSourceType.csv
          : CourseImportSourceType.excel;
      final result = await ref
          .read(courseScheduleImportServiceProvider)
          .prepareDraftFromSource(
            source: CourseImportSource(
              type: type,
              payload: input,
              filename: input.filename,
            ),
            semester: semester,
            template: _templateFor(semester, templates),
          );
      if (mounted) {
        setState(() {
          _draft = result.draft;
          _conflicts = result.conflicts;
        });
      }
    } on CourseImportException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = '无法解析课程文件：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectAll(bool selected) {
    final draft = _draft;
    if (draft == null) return;
    setState(() {
      _draft = draft.copyWith(
        courses: [
          for (final course in draft.courses)
            course.copyWith(selected: selected),
        ],
      );
    });
  }

  void _replaceCourse(int index, CourseImportCourseDraft course) {
    final draft = _draft;
    if (draft == null) return;
    final courses = [...draft.courses]..[index] = course;
    setState(() => _draft = draft.copyWith(courses: courses));
  }

  Future<void> _editCourse(int index, CourseImportCourseDraft course) async {
    final title = TextEditingController(text: course.title);
    final teacher = TextEditingController(text: course.teacher ?? '');
    final classroom = TextEditingController(text: course.classroom ?? '');
    final updated = await showDialog<CourseImportCourseDraft>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑课程'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: '课程名'),
              ),
              TextField(
                controller: teacher,
                decoration: const InputDecoration(labelText: '教师'),
              ),
              TextField(
                controller: classroom,
                decoration: const InputDecoration(labelText: '教室'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              course.copyWith(
                title: title.text.trim(),
                teacher: _clean(teacher.text),
                classroom: _clean(classroom.text),
                issues: course.issues
                    .where(
                      (issue) => issue.state == CourseImportFieldState.conflict,
                    )
                    .toList(),
              ),
            ),
            child: const Text('完成'),
          ),
        ],
      ),
    );
    title.dispose();
    teacher.dispose();
    classroom.dispose();
    if (updated != null) _replaceCourse(index, updated);
  }

  Future<void> _editRule(
    int courseIndex,
    int ruleIndex,
    CourseImportCourseDraft course,
  ) async {
    final rule = course.scheduleRules[ruleIndex];
    final start = TextEditingController(text: _formatTime(rule.startsAtMinute));
    final end = TextEditingController(text: _formatTime(rule.endsAtMinute));
    final startWeek = TextEditingController(text: '${rule.startWeek ?? ''}');
    final endWeek = TextEditingController(text: '${rule.endWeek ?? ''}');
    final customWeeks = TextEditingController(
      text: (rule.customWeeks.toList()..sort()).join(','),
    );
    var weekday = rule.weekday ?? DateTime.monday;
    var weekRule = rule.weekRuleType ?? CourseWeekRuleType.everyWeek;
    final updated = await showDialog<CourseImportScheduleRuleDraft>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('编辑课程安排'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: weekday,
                  decoration: const InputDecoration(labelText: '星期'),
                  items: [
                    for (var day = 1; day <= 7; day++)
                      DropdownMenuItem(
                        value: day,
                        child: Text('星期${'一二三四五六日'[day - 1]}'),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => weekday = value ?? weekday),
                ),
                TextField(
                  controller: start,
                  decoration: const InputDecoration(labelText: '开始时间 HH:mm'),
                ),
                TextField(
                  controller: end,
                  decoration: const InputDecoration(labelText: '结束时间 HH:mm'),
                ),
                DropdownButtonFormField<CourseWeekRuleType>(
                  initialValue: weekRule,
                  decoration: const InputDecoration(labelText: '周次规则'),
                  items: [
                    for (final value in CourseWeekRuleType.values)
                      DropdownMenuItem(
                        value: value,
                        child: Text(_weekRuleLabel(value)),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => weekRule = value ?? weekRule),
                ),
                TextField(
                  controller: startWeek,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '开始周'),
                ),
                TextField(
                  controller: endWeek,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '结束周'),
                ),
                if (weekRule == CourseWeekRuleType.custom)
                  TextField(
                    controller: customWeeks,
                    decoration: const InputDecoration(labelText: '自定义周次（逗号分隔）'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final startMinute = _parseTime(start.text);
                final endMinute = _parseTime(end.text);
                if (startMinute == null ||
                    endMinute == null ||
                    startMinute >= endMinute) {
                  return;
                }
                Navigator.pop(
                  context,
                  CourseImportScheduleRuleDraft(
                    weekday: weekday,
                    startsAtMinute: startMinute,
                    endsAtMinute: endMinute,
                    weekRuleType: weekRule,
                    startWeek: int.tryParse(startWeek.text),
                    endWeek: int.tryParse(endWeek.text),
                    customWeeks: weekRule == CourseWeekRuleType.custom
                        ? customWeeks.text
                              .split(RegExp(r'[,，\s]+'))
                              .map(int.tryParse)
                              .whereType<int>()
                              .toSet()
                        : const {},
                    timeMode: CourseScheduleTimeMode.customTime,
                    issues: rule.issues
                        .where(
                          (issue) =>
                              issue.state == CourseImportFieldState.conflict,
                        )
                        .toList(),
                  ),
                );
              },
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
    start.dispose();
    end.dispose();
    startWeek.dispose();
    endWeek.dispose();
    customWeeks.dispose();
    if (updated == null) return;
    final rules = [...course.scheduleRules]..[ruleIndex] = updated;
    _replaceCourse(courseIndex, course.copyWith(scheduleRules: rules));
  }

  Future<void> _confirm(
    SemesterDetails semester,
    List<ScheduleTemplateDetails> templates,
  ) async {
    final draft = _draft;
    if (draft == null) return;
    setState(() {
      _confirming = true;
      _error = null;
    });
    try {
      final count = await ref
          .read(courseScheduleImportServiceProvider)
          .confirmDraft(
            draft: draft,
            semester: semester,
            template: _templateFor(semester, templates),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导入 $count 门课程')));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = '导入失败：$error');
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  ScheduleTemplateDetails? _templateFor(
    SemesterDetails semester,
    List<ScheduleTemplateDetails> templates,
  ) => semester.scheduleTemplateId == null
      ? null
      : templates
            .where((item) => item.id == semester.scheduleTemplateId)
            .firstOrNull;

  int _warningCount(CourseImportDraft draft) => [
    ...draft.issues,
    ...draft.courses.expand(
      (course) => [
        ...course.issues,
        ...course.scheduleRules.expand((rule) => rule.issues),
      ],
    ),
  ].length;
  String? _clean(String value) => value.trim().isEmpty ? null : value.trim();
  String _formatTime(int? minute) => minute == null
      ? ''
      : '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
  int? _parseTime(String value) {
    final parts = value.trim().split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }
    return hour * 60 + minute;
  }
}

class _SpreadsheetCourseDraftCard extends StatelessWidget {
  const _SpreadsheetCourseDraftCard({
    required this.course,
    required this.onSelected,
    required this.onEditCourse,
    required this.onEditRule,
  });

  final CourseImportCourseDraft course;
  final ValueChanged<bool> onSelected;
  final VoidCallback onEditCourse;
  final ValueChanged<int> onEditRule;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: course.selected,
                onChanged: (value) => onSelected(value ?? false),
              ),
              Expanded(
                child: Text(
                  course.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: '编辑课程',
                onPressed: onEditCourse,
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          if ([course.teacher, course.classroom].whereType<String>().isNotEmpty)
            Text(
              [
                course.teacher,
                course.classroom,
              ].whereType<String>().join(' · '),
            ),
          for (var index = 0; index < course.scheduleRules.length; index++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(_ruleLabel(course.scheduleRules[index])),
              trailing: IconButton(
                tooltip: '编辑安排',
                onPressed: () => onEditRule(index),
                icon: const Icon(Icons.schedule_rounded),
              ),
            ),
          for (final issue in [
            ...course.issues,
            ...course.scheduleRules.expand((rule) => rule.issues),
          ])
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                issue.message,
                style: TextStyle(
                  color: issue.state == CourseImportFieldState.conflict
                      ? Colors.orange.shade800
                      : Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    ),
  );

  String _ruleLabel(CourseImportScheduleRuleDraft rule) =>
      '星期${rule.weekday == null ? '?' : '一二三四五六日'[rule.weekday! - 1]} · '
      '${_time(rule.startsAtMinute)}-${_time(rule.endsAtMinute)} · '
      '${_weekRuleLabel(rule.weekRuleType)}';
  String _time(int? minute) => minute == null
      ? '节次待匹配'
      : '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
}

class _SpreadsheetNotice extends StatelessWidget {
  const _SpreadsheetNotice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
}

String _weekRuleLabel(CourseWeekRuleType? type) => switch (type) {
  CourseWeekRuleType.everyWeek => '每周',
  CourseWeekRuleType.oddWeeks => '单周',
  CourseWeekRuleType.evenWeeks => '双周',
  CourseWeekRuleType.everyNWeeks => '每 N 周',
  CourseWeekRuleType.custom => '自定义周次',
  null => '周次待确认',
};
