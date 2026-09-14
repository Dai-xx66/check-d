// Dialog guard clauses stay compact to keep the preview interactions readable.
// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/course_providers.dart';
import '../data/course_document_import_adapter.dart';
import '../domain/course_import_models.dart';
import '../domain/course_models.dart';
import 'semester_settings_page.dart';

enum CourseDocumentKind { html, pdf }

class CourseDocumentImportPage extends ConsumerStatefulWidget {
  const CourseDocumentImportPage({required this.kind, super.key});

  final CourseDocumentKind kind;

  @override
  ConsumerState<CourseDocumentImportPage> createState() =>
      _CourseDocumentImportPageState();
}

class _CourseDocumentImportPageState
    extends ConsumerState<CourseDocumentImportPage> {
  PlatformFile? _file;
  String? _semesterId;
  int? _tableIndex;
  List<CourseDocumentTableCandidate> _tables = const [];
  CourseImportDraft? _draft;
  List<CourseImportConflict> _conflicts = const [];
  String? _error;
  bool _busy = false;

  bool get _isHtml => widget.kind == CourseDocumentKind.html;
  String get _label => _isHtml ? 'HTML 网页课表' : 'PDF 课程表';
  List<String> get _extensions =>
      _isHtml ? const ['html', 'htm'] : const ['pdf'];

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
      appBar: AppBar(title: Text('导入$_label')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        children: [
          Text(
            _isHtml
                ? '只读取已保存到本机的课表网页，不会登录学校网站，也不会上传文件。'
                : '只解析可复制文本的 PDF。扫描件请导出图片后使用课程表图片识别。',
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
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _semesterId = value;
                    _draft = null;
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
            onPressed: _busy ? null : _pickFile,
            icon: Icon(
              _isHtml ? Icons.language_rounded : Icons.picture_as_pdf_outlined,
            ),
            label: Text(_file == null ? '选择$_label文件' : _file!.name),
          ),
          if (_tables.length > 1) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _tableIndex,
              decoration: const InputDecoration(labelText: '网页中的课程表 *'),
              items: [
                for (final table in _tables)
                  DropdownMenuItem(
                    value: table.index,
                    child: Text(table.label),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                      _tableIndex = value;
                      _draft = null;
                    }),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _busy || _file == null || semester == null
                ? null
                : () => _prepare(semester, templates),
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.preview_outlined),
            label: Text(_busy ? '正在本地解析…' : '读取并预览课程'),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 14),
            _DocumentNotice(text: error),
          ],
          if (_draft case final draft?) ...[
            const SizedBox(height: 24),
            Text('检查课程', style: Theme.of(context).textTheme.titleLarge),
            Text(
              '来源：${_file!.name} · ${draft.courses.length} 门课程 · ${_issueCount(draft)} 个提示 · ${_conflicts.length} 个冲突',
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
            for (
              var courseIndex = 0;
              courseIndex < draft.courses.length;
              courseIndex++
            )
              _DocumentCourseCard(
                course: draft.courses[courseIndex],
                onSelected: (value) => _replaceCourse(
                  courseIndex,
                  draft.courses[courseIndex].copyWith(selected: value),
                ),
                onEditCourse: () =>
                    _editCourse(courseIndex, draft.courses[courseIndex]),
                onEditRule: (ruleIndex) => _editRule(
                  courseIndex,
                  ruleIndex,
                  draft.courses[courseIndex],
                ),
              ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy || !draft.canConfirm || semester == null
                  ? null
                  : () => _confirm(semester, templates),
              icon: const Icon(Icons.check_rounded),
              label: const Text('确认导入所选课程'),
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
        allowedExtensions: _extensions,
        withData: true,
      );
      final file = picked?.files.singleOrNull;
      if (file == null) return;
      if (file.bytes == null)
        throw const CourseImportException(
          CourseImportErrorCategory.fileReadFailed,
          '无法读取所选文件，请重新选择。',
        );
      final input = CourseDocumentFile(bytes: file.bytes!, filename: file.name);
      final tables = _isHtml
          ? await ref
                .read(courseDocumentImportAdapterProvider)
                .inspectHtml(input)
          : const <CourseDocumentTableCandidate>[];
      if (!mounted) return;
      setState(() {
        _file = file;
        _tables = tables;
        _tableIndex = tables.firstOrNull?.index;
        _draft = null;
        _conflicts = const [];
        _error = null;
      });
    } on CourseImportException catch (error) {
      if (mounted) setState(() => _error = error.message);
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
      _busy = true;
      _error = null;
      _draft = null;
      _conflicts = const [];
    });
    try {
      final input = CourseDocumentFile(
        bytes: file!.bytes!,
        filename: file.name,
        tableIndex: _tableIndex,
      );
      final result = await ref
          .read(courseScheduleImportServiceProvider)
          .prepareDraftFromSource(
            source: CourseImportSource(
              type: _isHtml
                  ? CourseImportSourceType.html
                  : CourseImportSourceType.pdf,
              payload: input,
              filename: input.filename,
            ),
            semester: semester,
            template: _templateFor(semester, templates),
          );
      if (mounted)
        setState(() {
          _draft = result.draft;
          _conflicts = result.conflicts;
        });
    } on CourseImportException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '解析课程文件时发生错误，请确认文件格式后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _selectAll(bool selected) {
    final draft = _draft;
    if (draft == null) return;
    setState(
      () => _draft = draft.copyWith(
        courses: [
          for (final course in draft.courses)
            course.copyWith(selected: selected),
        ],
      ),
    );
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
        content: Column(
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
                teacher: _optional(teacher.text),
                classroom: _optional(classroom.text),
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
    final start = TextEditingController(text: _time(rule.startsAtMinute));
    final end = TextEditingController(text: _time(rule.endsAtMinute));
    var weekday = rule.weekday ?? 1;
    var type = rule.weekRuleType ?? CourseWeekRuleType.everyWeek;
    final updated = await showDialog<CourseImportScheduleRuleDraft>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('编辑课程安排'),
          content: Column(
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
                initialValue: type,
                decoration: const InputDecoration(labelText: '周次规则'),
                items: [
                  for (final item in CourseWeekRuleType.values)
                    DropdownMenuItem(
                      value: item,
                      child: Text(_weekLabel(item)),
                    ),
                ],
                onChanged: (value) =>
                    setDialogState(() => type = value ?? type),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final from = _parseTime(start.text);
                final to = _parseTime(end.text);
                if (from == null || to == null || from >= to) return;
                Navigator.pop(
                  context,
                  CourseImportScheduleRuleDraft(
                    weekday: weekday,
                    startsAtMinute: from,
                    endsAtMinute: to,
                    weekRuleType: type,
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
      _busy = true;
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
      if (mounted) setState(() => _busy = false);
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
  int _issueCount(CourseImportDraft draft) => [
    ...draft.issues,
    ...draft.courses.expand(
      (course) => [
        ...course.issues,
        ...course.scheduleRules.expand((rule) => rule.issues),
      ],
    ),
  ].length;
  String? _optional(String value) => value.trim().isEmpty ? null : value.trim();
  String _time(int? minute) => minute == null
      ? ''
      : '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
  int? _parseTime(String value) {
    final parts = value.trim().split(':');
    final hour = parts.length == 2 ? int.tryParse(parts[0]) : null;
    final minute = parts.length == 2 ? int.tryParse(parts[1]) : null;
    return hour != null &&
            minute != null &&
            hour >= 0 &&
            hour <= 23 &&
            minute >= 0 &&
            minute <= 59
        ? hour * 60 + minute
        : null;
  }
}

class _DocumentCourseCard extends StatelessWidget {
  const _DocumentCourseCard({
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
                onPressed: onEditCourse,
                icon: const Icon(Icons.edit_outlined),
                tooltip: '编辑课程',
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
              title: Text(_rule(course.scheduleRules[index])),
              trailing: IconButton(
                onPressed: () => onEditRule(index),
                icon: const Icon(Icons.schedule_outlined),
                tooltip: '编辑安排',
              ),
            ),
          for (final issue in [
            ...course.issues,
            ...course.scheduleRules.expand((rule) => rule.issues),
          ])
            Text(
              issue.message,
              style: TextStyle(
                color: issue.state == CourseImportFieldState.conflict
                    ? Colors.orange.shade800
                    : Theme.of(context).colorScheme.error,
              ),
            ),
        ],
      ),
    ),
  );
  String _rule(CourseImportScheduleRuleDraft rule) =>
      '星期${rule.weekday == null ? '?' : '一二三四五六日'[rule.weekday! - 1]} · ${_format(rule.startsAtMinute)}-${_format(rule.endsAtMinute)} · ${_weekLabel(rule.weekRuleType)}';
  String _format(int? minute) => minute == null
      ? '待补充时间'
      : '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
}

class _DocumentNotice extends StatelessWidget {
  const _DocumentNotice({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
}

String _weekLabel(CourseWeekRuleType? value) => switch (value) {
  CourseWeekRuleType.everyWeek => '每周',
  CourseWeekRuleType.oddWeeks => '单周',
  CourseWeekRuleType.evenWeeks => '双周',
  CourseWeekRuleType.everyNWeeks => '每 N 周',
  CourseWeekRuleType.custom => '自定义周次',
  null => '周次待确认',
};
