import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../tags/presentation/tag_picker.dart';
import '../application/task_providers.dart';
import '../domain/task_models.dart';
import 'task_color_picker.dart';
import 'task_icon_picker.dart';

class OneTimeReminderFormPage extends ConsumerStatefulWidget {
  const OneTimeReminderFormPage({this.initialTask, super.key});

  final TaskDetails? initialTask;

  @override
  ConsumerState<OneTimeReminderFormPage> createState() =>
      _OneTimeReminderFormPageState();
}

class _OneTimeReminderFormPageState
    extends ConsumerState<OneTimeReminderFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _notesController;
  late DateTime _scheduledAt;
  late int _colorValue;
  late String _iconName;
  String? _tagId;
  late int? _remindBeforeMinutes;
  late OneTimeExecutionMode _executionMode;
  bool _isSaving = false;

  TaskDetails? get _initial => widget.initialTask;

  @override
  void initState() {
    super.initState();
    _tagId = _initial?.tagId;
    _nameController = TextEditingController(text: _initial?.name ?? '');
    _notesController = TextEditingController(text: _initial?.notes ?? '');
    _scheduledAt =
        _initial?.scheduledAt ?? DateTime.now().add(const Duration(hours: 1));
    _colorValue = _initial?.colorValue ?? taskColorValues[2];
    _iconName = _initial?.iconName ?? TaskIconKey.event;
    _remindBeforeMinutes = _initial?.remindBeforeMinutes;
    _executionMode =
        _initial?.oneTimeExecutionMode ?? OneTimeExecutionMode.normal;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_initial == null ? '创建单次事项提醒' : '编辑单次事项提醒'),
        backgroundColor: AppColors.background,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FormSection(
                      title: '事项信息',
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _nameController,
                            autofocus: _initial == null,
                            maxLength: 100,
                            decoration: const InputDecoration(
                              labelText: '名称',
                              hintText: '例如：项目会议',
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? '请输入事项名称'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TaskColorPicker(
                            selectedValue: _colorValue,
                            onSelected: (value) =>
                                setState(() => _colorValue = value),
                          ),
                          const SizedBox(height: 18),
                          TaskIconPicker(
                            selectedKey: _iconName,
                            color: Color(_colorValue),
                            onSelected: (value) =>
                                setState(() => _iconName = value),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _FormSection(
                      title: '执行方式',
                      child: SegmentedButton<OneTimeExecutionMode>(
                        segments: const [
                          ButtonSegment(
                            value: OneTimeExecutionMode.normal,
                            icon: Icon(Icons.check_circle_outline_rounded),
                            label: Text('普通事项'),
                          ),
                          ButtonSegment(
                            value: OneTimeExecutionMode.timer,
                            icon: Icon(Icons.timer_outlined),
                            label: Text('计时事项'),
                          ),
                        ],
                        selected: {_executionMode},
                        onSelectionChanged: (selection) =>
                            setState(() => _executionMode = selection.first),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _FormSection(
                      title: '日期与提醒',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final dateButton = OutlinedButton.icon(
                                onPressed: _pickDate,
                                icon: const Icon(Icons.calendar_today_rounded),
                                label: Text(
                                  DateFormat('yyyy年M月d日').format(_scheduledAt),
                                ),
                              );
                              final timeButton = OutlinedButton.icon(
                                onPressed: _pickTime,
                                icon: const Icon(Icons.schedule_rounded),
                                label: Text(
                                  DateFormat('HH:mm').format(_scheduledAt),
                                ),
                              );
                              if (constraints.maxWidth < 420) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    dateButton,
                                    const SizedBox(height: 10),
                                    timeButton,
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  Expanded(child: dateButton),
                                  const SizedBox(width: 10),
                                  Expanded(child: timeButton),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<int>(
                            key: ValueKey(_remindBeforeMinutes),
                            initialValue: _remindBeforeMinutes,
                            decoration: const InputDecoration(
                              labelText: '提前提醒（可选）',
                              prefixIcon: Icon(Icons.notifications_outlined),
                            ),
                            items: const [
                              DropdownMenuItem(value: 0, child: Text('事项开始时')),
                              DropdownMenuItem(
                                value: 10,
                                child: Text('提前 10 分钟'),
                              ),
                              DropdownMenuItem(
                                value: 30,
                                child: Text('提前 30 分钟'),
                              ),
                              DropdownMenuItem(
                                value: 60,
                                child: Text('提前 1 小时'),
                              ),
                              DropdownMenuItem(
                                value: 1440,
                                child: Text('提前 1 天'),
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => _remindBeforeMinutes = value),
                          ),
                          if (_remindBeforeMinutes != null)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () =>
                                    setState(() => _remindBeforeMinutes = null),
                                child: const Text('清除提醒'),
                              ),
                            ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _notesController,
                            minLines: 3,
                            maxLines: 6,
                            decoration: const InputDecoration(
                              labelText: '备注（可选）',
                              alignLabelWithHint: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_executionMode == OneTimeExecutionMode.timer) ...[
                      const SizedBox(height: 16),
                      TagPicker(
                        value: _tagId,
                        onChanged: (value) => setState(() => _tagId = value),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: const Icon(Icons.check_rounded),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        child: Text(_initial == null ? '创建事项' : '保存修改'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null) return;
    setState(() {
      _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        _scheduledAt.hour,
        _scheduledAt.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt),
    );
    if (time == null) return;
    setState(() {
      _scheduledAt = DateTime(
        _scheduledAt.year,
        _scheduledAt.month,
        _scheduledAt.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await ref
          .read(taskRepositoryProvider)
          .saveOneTimeReminder(
            OneTimeReminderDraft(
              name: _nameController.text,
              colorValue: _colorValue,
              iconName: _iconName,
              tagId: _executionMode == OneTimeExecutionMode.timer
                  ? _tagId
                  : null,
              scheduledAt: _scheduledAt,
              executionMode: _executionMode,
              remindBeforeMinutes: _remindBeforeMinutes,
              notes: _notesController.text,
            ),
            taskId: _initial?.id,
          );
      if (mounted) Navigator.of(context).pop();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存失败，请检查输入后重试')));
        setState(() => _isSaving = false);
      }
    }
  }
}

class _FormSection extends StatelessWidget {
  const _FormSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}
