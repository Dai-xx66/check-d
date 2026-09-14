import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../application/course_providers.dart';
import '../application/course_share_package_builder.dart';
import '../domain/course_models.dart';
import '../domain/course_share_models.dart';

class CourseSharePage extends ConsumerStatefulWidget {
  const CourseSharePage.single({required this.courseId, super.key})
    : semesterId = null;

  const CourseSharePage.semester({this.semesterId, super.key})
    : courseId = null;

  final String? courseId;
  final String? semesterId;

  @override
  ConsumerState<CourseSharePage> createState() => _CourseSharePageState();
}

class _CourseSharePageState extends ConsumerState<CourseSharePage> {
  bool _includeNotes = false;
  Duration _expiry = const Duration(days: 7);
  bool _creating = false;
  CreatedCourseShare? _created;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final courses = ref.watch(coursesProvider).value ?? const <CourseDetails>[];
    final semesters =
        ref.watch(semestersProvider).value ?? const <SemesterDetails>[];
    final templates =
        ref.watch(scheduleTemplatesProvider).value ??
        const <ScheduleTemplateDetails>[];
    final selection = _selection(courses, semesters, templates);
    final config = ref.watch(courseShareConfigProvider);
    return Scaffold(
      appBar: AppBar(title: Text(widget.courseId == null ? '分享本学期课表' : '分享课程')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        children: [
          Text(
            selection == null
                ? '没有找到可分享的课程。'
                : '将复制 ${selection.courses.length} 门课程的课程配置。接收方导入后拥有独立副本。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('包含课程备注'),
            subtitle: const Text('默认关闭，避免分享可能含有私人内容的备注。'),
            value: _includeNotes,
            onChanged: _creating
                ? null
                : (value) => setState(() {
                    _includeNotes = value;
                    _created = null;
                  }),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<Duration>(
            initialValue: _expiry,
            decoration: const InputDecoration(labelText: '分享有效期'),
            items: [
              for (final duration in config.allowedExpiries)
                DropdownMenuItem(
                  value: duration,
                  child: Text('${duration.inDays} 天'),
                ),
            ],
            onChanged: _creating
                ? null
                : (value) => setState(() {
                    _expiry = value ?? config.defaultExpiry;
                    _created = null;
                  }),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _creating || selection == null
                ? null
                : () => _create(selection),
            icon: _creating
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share_rounded),
            label: Text(_creating ? '正在生成…' : '生成分享口令'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_created case final created?) ...[
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      '分享口令',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      created.code,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    Semantics(
                      label: '课程分享二维码 ${created.code}',
                      child: ColoredBox(
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: QrImageView(data: created.deepLink, size: 210),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('有效至 ${_dateTime(created.expiresAt)}'),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: created.code),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('分享口令已复制')),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('复制口令'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  _ShareSelection? _selection(
    List<CourseDetails> courses,
    List<SemesterDetails> semesters,
    List<ScheduleTemplateDetails> templates,
  ) {
    if (widget.courseId case final courseId?) {
      final course = courses.where((item) => item.id == courseId).firstOrNull;
      if (course == null) return null;
      final semester = semesters
          .where((item) => item.id == course.semesterId)
          .firstOrNull;
      return _ShareSelection(
        courses: [course],
        semester: semester,
        template: _templateFor(semester, templates),
      );
    }
    final semester = widget.semesterId == null
        ? semesters.where((item) => item.isCurrent).firstOrNull
        : semesters.where((item) => item.id == widget.semesterId).firstOrNull;
    if (semester == null) return null;
    final selected = courses
        .where((course) => course.semesterId == semester.id)
        .toList();
    if (selected.isEmpty) return null;
    return _ShareSelection(
      courses: selected,
      semester: semester,
      template: _templateFor(semester, templates),
    );
  }

  ScheduleTemplateDetails? _templateFor(
    SemesterDetails? semester,
    List<ScheduleTemplateDetails> templates,
  ) => semester?.scheduleTemplateId == null
      ? null
      : templates
            .where((item) => item.id == semester!.scheduleTemplateId)
            .firstOrNull;

  Future<void> _create(_ShareSelection selection) async {
    setState(() {
      _creating = true;
      _error = null;
      _created = null;
    });
    try {
      final package = CourseSharePackageBuilder.build(
        courses: selection.courses,
        semester: selection.semester,
        template: selection.template,
        includeNotes: _includeNotes,
      );
      final created = await ref
          .read(courseShareRepositoryProvider)
          .createShare(package, expiry: _expiry);
      if (mounted) setState(() => _created = created);
    } on CourseShareException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = '无法创建课程分享：$error');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  String _dateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _ShareSelection {
  const _ShareSelection({
    required this.courses,
    required this.semester,
    required this.template,
  });

  final List<CourseDetails> courses;
  final SemesterDetails? semester;
  final ScheduleTemplateDetails? template;
}
