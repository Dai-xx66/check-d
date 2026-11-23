import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/app_time.dart';
import '../../profile/application/reminder_defaults_providers.dart';
import '../../schedule/application/day_schedule_providers.dart';
import '../../schedule/domain/day_schedule_models.dart';
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
  final _nameFocusNode = FocusNode();
  late final TextEditingController _nameController;
  late final TextEditingController _notesController;
  DateTime? _scheduledAt;
  DateTime? _availableFrom;
  DateTime? _plannedDate;
  TaskDeadline? _deadline;
  late int _colorValue;
  late String _iconName;
  String? _tagId;
  late int? _remindBeforeMinutes;
  late bool _advanceReminderEnabled;
  bool _atTimeReminderEnabled = false;
  late OneTimeExecutionMode _executionMode;
  bool _isSaving = false;

  TaskDetails? get _initial => widget.initialTask;

  @override
  void initState() {
    super.initState();
    _tagId = _initial?.tagId;
    _nameController = TextEditingController(text: _initial?.name ?? '');
    _notesController = TextEditingController(text: _initial?.notes ?? '');
    _scheduledAt = _initial?.scheduledAt;
    _availableFrom = _initial?.availableFrom;
    _plannedDate =
        _initial?.plannedDate ??
        (_scheduledAt == null ? null : dateOnly(_scheduledAt!));
    _deadline = _initial?.deadline;
    _colorValue = _initial?.colorValue ?? taskColorValues[2];
    _iconName = _initial?.iconName ?? TaskIconKey.event;
    _remindBeforeMinutes = _initial?.remindBeforeMinutes;
    _advanceReminderEnabled = _remindBeforeMinutes != null;
    _executionMode =
        _initial?.oneTimeExecutionMode ?? OneTimeExecutionMode.untimed;
    _loadInitialReminderSettings();
  }

  Future<void> _loadInitialReminderSettings() async {
    if (_initial == null) {
      final defaults = await ref
          .read(reminderDefaultsRepositoryProvider)
          .load();
      if (!mounted) return;
      setState(() {
        _advanceReminderEnabled = defaults.advanceEnabled;
        _remindBeforeMinutes = defaults.advanceMinutes;
        _atTimeReminderEnabled = defaults.atTimeEnabled;
      });
      return;
    }
    final rules = await ref
        .read(dayScheduleRepositoryProvider)
        .loadReminderRules();
    if (!mounted) return;
    final ownRules = rules
        .where(
          (rule) =>
              rule.ownerType == DayItemType.oneTime &&
              rule.ownerId == _initial!.id &&
              rule.localDate == null,
        )
        .toList();
    if (ownRules.isEmpty) return;
    final advance = ownRules.where(
      (rule) => rule.reminderKind == ReminderKind.advance,
    );
    final due = ownRules.where((rule) => rule.reminderKind == ReminderKind.due);
    setState(() {
      _advanceReminderEnabled = advance.firstOrNull?.enabled ?? false;
      _remindBeforeMinutes = advance.firstOrNull?.remindBeforeMinutes ?? 10;
      _atTimeReminderEnabled = due.firstOrNull?.enabled ?? false;
    });
  }

  @override
  void dispose() {
    _nameFocusNode.dispose();
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_initial == null ? '创建单次事项' : '编辑单次事项'),
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
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FormSection(
                      title: '基本信息',
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _nameController,
                            focusNode: _nameFocusNode,
                            autofocus: _initial == null,
                            maxLength: 100,
                            decoration: const InputDecoration(
                              labelText: '任务名称',
                              hintText: '例如：项目会议',
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? '请填写任务名称'
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
                            value: OneTimeExecutionMode.untimed,
                            icon: Icon(Icons.check_circle_outline_rounded),
                            label: Text('不计时'),
                          ),
                          ButtonSegment(
                            value: OneTimeExecutionMode.timed,
                            icon: Icon(Icons.timer_outlined),
                            label: Text('计时'),
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
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('可开始日期'),
                            subtitle: const Text('到这一天后，事项才会进入待完成'),
                            value: _availableFrom != null,
                            onChanged: (enabled) => setState(() {
                              _availableFrom = enabled
                                  ? dateOnly(DateTime.now())
                                  : null;
                            }),
                          ),
                          if (_availableFrom != null)
                            _DateChoiceButton(
                              label: '选择可开始日期',
                              value: _availableFrom!,
                              onPressed: _pickAvailableDate,
                            ),
                          const Divider(height: 28),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('安排执行日期'),
                            subtitle: const Text('只表示计划什么时候做，不是截止时间'),
                            value: _plannedDate != null,
                            onChanged: (enabled) => setState(() {
                              if (enabled) {
                                _plannedDate = dateOnly(DateTime.now());
                              } else {
                                _plannedDate = null;
                                _scheduledAt = null;
                              }
                            }),
                          ),
                          if (_plannedDate != null) ...[
                            _DateChoiceButton(
                              label: '选择计划日期',
                              value: _plannedDate!,
                              onPressed: _pickPlannedDate,
                            ),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('设置具体时间'),
                              subtitle: const Text('使用 24 小时制安排到时间轴'),
                              value: _scheduledAt != null,
                              onChanged: (enabled) => setState(() {
                                _scheduledAt = enabled
                                    ? DateTime(
                                        _plannedDate!.year,
                                        _plannedDate!.month,
                                        _plannedDate!.day,
                                        9,
                                      )
                                    : null;
                              }),
                            ),
                            if (_scheduledAt != null)
                              OutlinedButton.icon(
                                onPressed: _pickTime,
                                icon: const Icon(Icons.schedule_rounded),
                                label: Text(
                                  '选择具体时间 · ${DateFormat('HH:mm').format(_scheduledAt!)}',
                                ),
                              ),
                          ],
                          const Divider(height: 28),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('截止时间'),
                            subtitle: const Text('最晚需要完成的日期，可不设置'),
                            value: _deadline != null,
                            onChanged: (enabled) => setState(() {
                              _deadline = enabled
                                  ? TaskDeadline.dateOnly(DateTime.now())
                                  : null;
                            }),
                          ),
                          if (_deadline != null) ...[
                            _DateChoiceButton(
                              label: '选择截止日期',
                              value: _deadline!.localDate,
                              onPressed: _pickDeadlineDate,
                            ),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('指定截止时间'),
                              subtitle: const Text('关闭时，截止日期当天全天有效'),
                              value: _deadline!.hasTime,
                              onChanged: (enabled) => setState(() {
                                final date = _deadline!.localDate;
                                _deadline = enabled == true
                                    ? TaskDeadline.exact(
                                        DateTime(
                                          date.year,
                                          date.month,
                                          date.day,
                                          18,
                                        ),
                                      )
                                    : TaskDeadline.dateOnly(date);
                              }),
                            ),
                            if (_deadline!.hasTime)
                              OutlinedButton.icon(
                                onPressed: _pickDeadlineTime,
                                icon: const Icon(Icons.timer_outlined),
                                label: Text(
                                  '选择截止时间 · ${DateFormat('HH:mm').format(_deadline!.at!)}',
                                ),
                              ),
                          ],
                          const Divider(height: 28),
                          if (_scheduledAt == null)
                            Text(
                              '只有设置具体执行时间后，才能开启提前提醒和到点提醒。',
                              style: TextStyle(color: AppColors.muted),
                            )
                          else ...[
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('提前提醒'),
                              subtitle: const Text('在事项开始前发送通知'),
                              value: _advanceReminderEnabled,
                              onChanged: (value) => setState(() {
                                _advanceReminderEnabled = value;
                                _remindBeforeMinutes ??= 10;
                              }),
                            ),
                            if (_advanceReminderEnabled)
                              DropdownButtonFormField<int>(
                                initialValue: _remindBeforeMinutes ?? 10,
                                decoration: const InputDecoration(
                                  labelText: '提前多久',
                                  prefixIcon: Icon(
                                    Icons.notifications_outlined,
                                  ),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 5,
                                    child: Text('提前 5 分钟'),
                                  ),
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
                                ],
                                onChanged: (value) => setState(
                                  () => _remindBeforeMinutes = value,
                                ),
                              ),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('到点提醒'),
                              subtitle: const Text('在事项开始时发送通知'),
                              value: _atTimeReminderEnabled,
                              onChanged: (value) => setState(
                                () => _atTimeReminderEnabled = value,
                              ),
                            ),
                          ],
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
                    if (_executionMode == OneTimeExecutionMode.timed) ...[
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

  Future<DateTime?> _pickDateValue(DateTime initialDate) {
    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
  }

  Future<void> _pickAvailableDate() async {
    final date = await _pickDateValue(_availableFrom ?? DateTime.now());
    if (date == null) return;
    setState(() => _availableFrom = dateOnly(date));
  }

  Future<void> _pickPlannedDate() async {
    final date = await _pickDateValue(_plannedDate ?? DateTime.now());
    if (date == null) return;
    setState(() {
      _plannedDate = dateOnly(date);
      if (_scheduledAt != null) {
        _scheduledAt = DateTime(
          date.year,
          date.month,
          date.day,
          _scheduledAt!.hour,
          _scheduledAt!.minute,
        );
      }
    });
  }

  Future<void> _pickDeadlineDate() async {
    final current = _deadline!;
    final date = await _pickDateValue(current.localDate);
    if (date == null) return;
    setState(() {
      _deadline = current.isDateOnly
          ? TaskDeadline.dateOnly(date)
          : TaskDeadline.exact(
              DateTime(
                date.year,
                date.month,
                date.day,
                current.at!.hour,
                current.at!.minute,
              ),
            );
    });
  }

  Future<void> _pickDeadlineTime() async {
    final current = _deadline!;
    final time = await showAppTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current.at!),
      helpText: '选择截止时间',
    );
    if (time == null) return;
    final date = current.localDate;
    setState(() {
      _deadline = TaskDeadline.exact(
        DateTime(date.year, date.month, date.day, time.hour, time.minute),
      );
    });
  }

  Future<void> _pickTime() async {
    final time = await showAppTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt ?? DateTime.now()),
    );
    if (time == null) return;
    setState(() {
      _scheduledAt = DateTime(
        _scheduledAt?.year ?? DateTime.now().year,
        _scheduledAt?.month ?? DateTime.now().month,
        _scheduledAt?.day ?? DateTime.now().day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      _nameFocusNode.requestFocus();
      return;
    }
    setState(() => _isSaving = true);
    try {
      final taskId = await ref
          .read(taskRepositoryProvider)
          .saveOneTimeReminder(
            OneTimeReminderDraft(
              name: _nameController.text,
              colorValue: _colorValue,
              iconName: _iconName,
              tagId: _executionMode == OneTimeExecutionMode.timed
                  ? _tagId
                  : null,
              scheduledAt: _scheduledAt,
              availableFrom: _availableFrom,
              plannedDate: _plannedDate,
              deadline: _deadline,
              executionMode: _executionMode,
              remindBeforeMinutes: _remindBeforeMinutes,
              notes: _notesController.text,
            ),
            taskId: _initial?.id,
          );
      await ref
          .read(dayScheduleRepositoryProvider)
          .replaceReminderConfiguration(
            ownerType: DayItemType.oneTime,
            ownerId: taskId,
            advanceEnabled: _scheduledAt != null && _advanceReminderEnabled,
            advanceMinutes: _advanceReminderEnabled
                ? (_remindBeforeMinutes ?? 10)
                : null,
            atTimeEnabled: _scheduledAt != null && _atTimeReminderEnabled,
          );
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_saveErrorMessage(error))));
        setState(() => _isSaving = false);
      }
    }
  }

  String _saveErrorMessage(Object error) {
    if (error is ArgumentError) {
      final message = error.message;
      if (message != null && message.toString().trim().isNotEmpty) {
        return message.toString();
      }
    }
    return '保存失败，请检查输入后重试';
  }
}

class _DateChoiceButton extends StatelessWidget {
  const _DateChoiceButton({
    required this.label,
    required this.value,
    required this.onPressed,
  });

  final String label;
  final DateTime value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.calendar_today_rounded),
    label: Text('$label · ${DateFormat('yyyy年M月d日').format(value)}'),
  );
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
