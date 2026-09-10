import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../application/course_providers.dart';
import '../data/course_schedule_recognizer.dart';
import '../domain/course_models.dart';
import '../domain/course_schedule_import_models.dart';
import 'schedule_template_page.dart';
import 'semester_settings_page.dart';

class CourseScheduleImportPage extends ConsumerStatefulWidget {
  const CourseScheduleImportPage({super.key});

  @override
  ConsumerState<CourseScheduleImportPage> createState() =>
      _CourseScheduleImportPageState();
}

class _CourseScheduleImportPageState
    extends ConsumerState<CourseScheduleImportPage> {
  String? _semesterId;
  PlatformFile? _image;
  CourseImportPlan? _plan;
  bool _recognizing = false;
  bool _importing = false;
  bool _createDetectedTemplate = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final semesters =
        ref.watch(semestersProvider).value ?? const <SemesterDetails>[];
    final templates =
        ref.watch(scheduleTemplatesProvider).value ??
        const <ScheduleTemplateDetails>[];
    final current = semesters.where((item) => item.isCurrent).firstOrNull;
    _semesterId ??= current?.id;
    final semester = semesters
        .where((item) => item.id == _semesterId)
        .firstOrNull;
    final template = semester?.scheduleTemplateId == null
        ? null
        : templates
              .where((item) => item.id == semester!.scheduleTemplateId)
              .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('从课程表导入')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        children: [
          Text(
            '导入前先选择学期和课程表截图。识别结果会先进入可修改的草稿，不会自动保存课程。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            value: _semesterId,
            decoration: const InputDecoration(labelText: '目标学期 *'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('请选择学期'),
              ),
              ...semesters.map(
                (item) => DropdownMenuItem(
                  value: item.id,
                  child: Text(item.isCurrent ? '${item.name}（当前）' : item.name),
                ),
              ),
            ],
            onChanged: _recognizing
                ? null
                : (value) => setState(() {
                    _semesterId = value;
                    _plan = null;
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
            onPressed: _recognizing ? null : _pickImage,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(_image == null ? '选择课程表图片' : _image!.name),
          ),
          const SizedBox(height: 8),
          Text(
            '本地识别 · 图片不会上传。支持 PNG、JPG、JPEG。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _recognizing || _image == null || semester == null
                ? null
                : () => _recognize(semester, template),
            icon: _recognizing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_outlined),
            label: Text(_recognizing ? '正在识别课程表…' : '开始识别'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            _Notice(icon: Icons.error_outline_rounded, text: _error!),
          ],
          if (_plan != null) ...[
            const SizedBox(height: 26),
            _Preview(
              plan: _plan!,
              createDetectedTemplate: _createDetectedTemplate,
              onTemplateChoice: (value) =>
                  setState(() => _createDetectedTemplate = value),
              onChanged: () => setState(() {}),
              onOpenTemplates: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ScheduleTemplatePage()),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _importing || !_canConfirm ? null : _confirm,
              icon: _importing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_importing ? '正在导入…' : '确认导入'),
            ),
          ],
        ],
      ),
    );
  }

  bool get _canConfirm {
    final plan = _plan;
    if (plan == null || !plan.courses.any((course) => course.selected))
      return false;
    return plan.canImport ||
        (_createDetectedTemplate && plan.templateDraft != null);
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg'],
        withData: true,
      );
      final file = result?.files.singleOrNull;
      if (file == null) return;
      if (file.bytes == null) {
        setState(() => _error = '无法读取所选图片，请重新选择。');
        return;
      }
      setState(() {
        _image = file;
        _plan = null;
        _error = null;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(
        () => _error = '无法打开图片选择器：${error.message ?? '请检查应用的文件访问权限后重试。'}',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '无法打开图片选择器，请稍后重试。');
    }
  }

  Future<void> _recognize(
    SemesterDetails semester,
    ScheduleTemplateDetails? template,
  ) async {
    final image = _image;
    if (image?.bytes == null) return;
    setState(() {
      _recognizing = true;
      _error = null;
      _plan = null;
    });
    try {
      final result = await ref
          .read(courseScheduleRecognizerProvider)
          .recognize(
            bytes: image!.bytes!,
            filename: image.name,
            mimeType: _mimeType(image.extension),
          );
      if (result.courses.isEmpty)
        throw const CourseScheduleRecognitionUnavailable(
          '没有识别到课程，请更换清晰完整的课程表截图。',
        );
      final plan = await ref
          .read(courseScheduleImportServiceProvider)
          .prepare(semester: semester, template: template, result: result);
      if (!mounted) return;
      setState(() {
        _plan = plan;
        // Creating a template is never an implicit side effect of recognition.
        _createDetectedTemplate = false;
      });
    } on CourseScheduleRecognitionUnavailable catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = '课程表识别失败：$error');
    } finally {
      if (mounted) setState(() => _recognizing = false);
    }
  }

  Future<void> _confirm() async {
    final plan = _plan;
    if (plan == null) return;
    setState(() => _importing = true);
    try {
      final count = await ref
          .read(courseScheduleImportServiceProvider)
          .confirm(
            plan: plan,
            createRecognizedTemplate: _createDetectedTemplate,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导入 $count 门课程')));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = '导入失败：$error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  String _mimeType(String? extension) => switch (extension?.toLowerCase()) {
    'png' => 'image/png',
    _ => 'image/jpeg',
  };
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.plan,
    required this.createDetectedTemplate,
    required this.onTemplateChoice,
    required this.onChanged,
    required this.onOpenTemplates,
  });
  final CourseImportPlan plan;
  final bool createDetectedTemplate;
  final ValueChanged<bool> onTemplateChoice;
  final VoidCallback onChanged;
  final VoidCallback onOpenTemplates;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('检查课程', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(
        '识别到 ${plan.courses.length} 门课程；确认导入前可以修改或取消。',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      if (plan.needsTemplate)
        _Notice(
          icon: Icons.schedule_outlined,
          text: '无法确定课程节次时间，请先设置作息模板。',
          action: TextButton(
            onPressed: onOpenTemplates,
            child: const Text('去设置'),
          ),
        )
      else if (plan.templateTimeConflict) ...[
        _Notice(
          icon: Icons.warning_amber_rounded,
          text: '识别到的作息时间与当前模板不一致。不会修改当前模板。',
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('创建新的识别作息模板并绑定此学期'),
          subtitle: const Text('关闭后继续使用当前作息模板。'),
          value: createDetectedTemplate,
          onChanged: onTemplateChoice,
        ),
      ] else if (plan.template == null && plan.templateDraft != null) ...[
        _Notice(
          icon: Icons.schedule_outlined,
          text: '识别到课程作息时间。创建前仍可返回作息模板页面调整。',
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('创建识别到的作息模板并使用'),
          value: createDetectedTemplate,
          onChanged: onTemplateChoice,
        ),
      ],
      ...plan.courses.map(
        (course) => _CourseDraftCard(
          course: course,
          template: plan.template,
          onChanged: onChanged,
        ),
      ),
    ],
  );
}

class _CourseDraftCard extends StatefulWidget {
  const _CourseDraftCard({
    required this.course,
    required this.template,
    required this.onChanged,
  });
  final RecognizedCourseDraft course;
  final ScheduleTemplateDetails? template;
  final VoidCallback onChanged;
  @override
  State<_CourseDraftCard> createState() => _CourseDraftCardState();
}

class _CourseDraftCardState extends State<_CourseDraftCard> {
  late final TextEditingController _name = TextEditingController(
    text: widget.course.name,
  );
  late final TextEditingController _teacher = TextEditingController(
    text: widget.course.teacher ?? '',
  );
  late final TextEditingController _room = TextEditingController(
    text: widget.course.classroom ?? '',
  );
  @override
  void dispose() {
    _name.dispose();
    _teacher.dispose();
    _room.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('导入这门课程'),
            value: widget.course.selected,
            onChanged: (value) {
              setState(() => widget.course.selected = value ?? false);
              widget.onChanged();
            },
          ),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: '课程名称'),
            onChanged: (value) {
              widget.course.name = value;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _teacher,
            decoration: const InputDecoration(labelText: '教师（可选）'),
            onChanged: (value) =>
                widget.course.teacher = value.trim().isEmpty ? null : value,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _room,
            decoration: const InputDecoration(labelText: '教室（可选）'),
            onChanged: (value) =>
                widget.course.classroom = value.trim().isEmpty ? null : value,
          ),
          for (final rule in widget.course.rules)
            _RuleDraftEditor(
              rule: rule,
              template: widget.template,
              onChanged: widget.onChanged,
            ),
          for (final warning in widget.course.warnings)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '⚠ ${warning.message}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
  );
}

class _RuleDraftEditor extends StatelessWidget {
  const _RuleDraftEditor({
    required this.rule,
    required this.template,
    required this.onChanged,
  });
  final RecognizedScheduleRuleDraft rule;
  final ScheduleTemplateDetails? template;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<int?>(
          value: rule.weekday,
          decoration: const InputDecoration(labelText: '星期'),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('请选择')),
            for (var day = 1; day <= 7; day++)
              DropdownMenuItem(
                value: day,
                child: Text('星期${'一二三四五六日'[day - 1]}'),
              ),
          ],
          onChanged: (value) {
            rule.weekday = value;
            onChanged();
          },
        ),
        const SizedBox(height: 8),
        if (template != null)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: template!.segments
                .where(
                  (item) => item.segmentType == ScheduleSegmentType.classTime,
                )
                .map(
                  (segment) => FilterChip(
                    label: Text(segment.name),
                    selected: rule.mappedSegmentIds.contains(segment.id),
                    onSelected: (selected) {
                      if (selected)
                        rule.mappedSegmentIds.add(segment.id);
                      else
                        rule.mappedSegmentIds.remove(segment.id);
                      onChanged();
                    },
                  ),
                )
                .toList(),
          )
        else
          const Text('将在确认创建作息模板后映射节次。'),
        const SizedBox(height: 8),
        DropdownButtonFormField<CourseWeekRuleType?>(
          value: rule.weekRuleType,
          decoration: const InputDecoration(labelText: '周次规则'),
          items: const [
            DropdownMenuItem(
              value: CourseWeekRuleType.everyWeek,
              child: Text('每周'),
            ),
            DropdownMenuItem(
              value: CourseWeekRuleType.oddWeeks,
              child: Text('单周'),
            ),
            DropdownMenuItem(
              value: CourseWeekRuleType.evenWeeks,
              child: Text('双周'),
            ),
            DropdownMenuItem(
              value: CourseWeekRuleType.everyNWeeks,
              child: Text('每 N 周'),
            ),
            DropdownMenuItem(
              value: CourseWeekRuleType.custom,
              child: Text('自定义周次'),
            ),
          ],
          onChanged: (value) {
            rule.weekRuleType = value;
            rule.weekRuleConfirmed = value != null;
            onChanged();
          },
        ),
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
          if (action != null) action!,
        ],
      ),
    ),
  );
}
