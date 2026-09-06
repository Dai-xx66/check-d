import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../application/course_providers.dart';
import '../domain/course_models.dart';

class ScheduleTemplatePage extends ConsumerWidget {
  const ScheduleTemplatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(scheduleTemplatesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('作息模板')),
      body: templates.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('作息模板加载失败：$error')),
        data: (items) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
          children: [
            Text('定义一天的节次与准确时间', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 14),
            if (items.isEmpty)
              const _TemplateEmptyState()
            else
              ...items.map(
                (template) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _TemplateCard(
                    template: template,
                    onEdit: () => _openEditor(context, template),
                    onDelete: () => _confirmDelete(context, ref, template),
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('新建作息模板'),
      ),
    );
  }

  void _openEditor(BuildContext context, [ScheduleTemplateDetails? template]) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ScheduleTemplateEditorPage(initialTemplate: template),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ScheduleTemplateDetails template,
  ) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除作息模板？'),
        content: Text('“${template.name}”会从模板列表中移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (accepted != true || !context.mounted) return;
    try {
      await ref
          .read(courseRepositoryProvider)
          .archiveScheduleTemplate(template.id);
    } on StateError catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class ScheduleTemplateEditorPage extends ConsumerStatefulWidget {
  const ScheduleTemplateEditorPage({super.key, this.initialTemplate});

  final ScheduleTemplateDetails? initialTemplate;

  @override
  ConsumerState<ScheduleTemplateEditorPage> createState() =>
      _ScheduleTemplateEditorPageState();
}

class _ScheduleTemplateEditorPageState
    extends ConsumerState<ScheduleTemplateEditorPage> {
  final _nameController = TextEditingController();
  late List<_PeriodDraft> _periods;
  bool _isDefault = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final template = widget.initialTemplate;
    _nameController.text = template?.name ?? '';
    _isDefault = template?.isDefault ?? false;
    _periods = template == null
        ? [_PeriodDraft.defaultAt(0)]
        : template.segments
              .where(
                (segment) =>
                    segment.segmentType == ScheduleSegmentType.classTime,
              )
              .map(_PeriodDraft.fromSegment)
              .toList();
    if (_periods.isEmpty) _periods = [_PeriodDraft.defaultAt(0)];
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final period in _periods) {
      period.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialTemplate == null ? '新建作息模板' : '编辑作息模板'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: '模板名称 *'),
          ),
          const SizedBox(height: 6),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('设为默认模板'),
            subtitle: const Text('新建课程时可优先使用这套节次'),
            value: _isDefault,
            onChanged: (value) => setState(() => _isDefault = value),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text(
                  '节次',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: _addPeriod,
                icon: const Icon(Icons.add_rounded),
                label: const Text('新增节次'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...List.generate(
            _periods.length,
            (index) => _PeriodEditorRow(
              index: index,
              draft: _periods[index],
              onChanged: () => setState(() {}),
              onMoveUp: index == 0 ? null : () => _move(index, index - 1),
              onMoveDown: index == _periods.length - 1
                  ? null
                  : () => _move(index, index + 1),
              onDelete: _periods.length == 1 ? null : () => _remove(index),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: const Text('保存模板'),
          ),
        ],
      ),
    );
  }

  void _addPeriod() {
    setState(() => _periods.add(_PeriodDraft.defaultAt(_periods.length)));
  }

  void _remove(int index) {
    final removed = _periods.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  void _move(int from, int to) {
    setState(() {
      final period = _periods.removeAt(from);
      _periods.insert(to, period);
    });
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      _showError('请填写模板名称');
      return;
    }
    final segments = <ScheduleTemplateSegmentDraft>[];
    for (var index = 0; index < _periods.length; index++) {
      final period = _periods[index];
      final name = period.name.text.trim();
      final start = period.start.hour * 60 + period.start.minute;
      final end = period.end.hour * 60 + period.end.minute;
      if (name.isEmpty) {
        _showError('请填写第${index + 1}节名称');
        return;
      }
      if (end <= start) {
        _showError('“$name”的结束时间必须晚于开始时间');
        return;
      }
      segments.add(
        ScheduleTemplateSegmentDraft(
          id: period.id,
          name: name,
          startsAtMinute: start,
          endsAtMinute: end,
          sortOrder: index,
        ),
      );
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(courseRepositoryProvider)
          .saveScheduleTemplate(
            ScheduleTemplateDraft(
              name: _nameController.text,
              isDefault: _isDefault,
              segments: segments,
            ),
            templateId: widget.initialTemplate?.id,
          );
      if (mounted) Navigator.pop(context);
    } on ArgumentError catch (error) {
      _showError(error.message.toString());
    } on StateError catch (error) {
      _showError(error.message.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.onEdit,
    required this.onDelete,
  });
  final ScheduleTemplateDetails template;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: AppColors.blueMist,
        foregroundColor: AppColors.cyan,
        child: const Icon(Icons.schedule_rounded),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              template.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (template.isDefault) const _CurrentBadge(label: '默认'),
        ],
      ),
      subtitle: Text(
        '${template.segments.where((item) => item.segmentType == ScheduleSegmentType.classTime).length} 节 · ${_summary(template)}',
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('编辑')),
          PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
      ),
      onTap: onEdit,
    ),
  );

  String _summary(ScheduleTemplateDetails template) {
    final periods = template.segments
        .where((item) => item.segmentType == ScheduleSegmentType.classTime)
        .toList();
    if (periods.isEmpty) return '尚未设置节次';
    return '${_format(periods.first.startsAtMinute)}–${_format(periods.last.endsAtMinute)}';
  }

  String _format(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
}

class _PeriodEditorRow extends StatelessWidget {
  const _PeriodEditorRow({
    required this.index,
    required this.draft,
    required this.onChanged,
    this.onMoveUp,
    this.onMoveDown,
    this.onDelete,
  });
  final int index;
  final _PeriodDraft draft;
  final VoidCallback onChanged;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '第${index + 1}节',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              IconButton(
                tooltip: '上移',
                onPressed: onMoveUp,
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
              ),
              IconButton(
                tooltip: '下移',
                onPressed: onMoveDown,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
              IconButton(
                tooltip: '删除',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          TextField(
            controller: draft.name,
            decoration: const InputDecoration(labelText: '节次名称'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _TimeButton(
                  label: '开始',
                  value: draft.start,
                  onChanged: (value) {
                    draft.start = value;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TimeButton(
                  label: '结束',
                  value: draft.end,
                  onChanged: (value) {
                    draft.end = value;
                    onChanged();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final TimeOfDay value;
  final ValueChanged<TimeOfDay> onChanged;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: () async {
      final picked = await showTimePicker(context: context, initialTime: value);
      if (picked != null) onChanged(picked);
    },
    child: Text('$label\n${value.format(context)}'),
  );
}

class _PeriodDraft {
  _PeriodDraft({
    this.id,
    required String name,
    required this.start,
    required this.end,
  }) : name = TextEditingController(text: name);
  factory _PeriodDraft.fromSegment(ScheduleTemplateSegment segment) =>
      _PeriodDraft(
        id: segment.id,
        name: segment.name,
        start: TimeOfDay(
          hour: segment.startsAtMinute ~/ 60,
          minute: segment.startsAtMinute % 60,
        ),
        end: TimeOfDay(
          hour: segment.endsAtMinute ~/ 60,
          minute: segment.endsAtMinute % 60,
        ),
      );
  factory _PeriodDraft.defaultAt(int index) => _PeriodDraft(
    name: '第${index + 1}节',
    start: TimeOfDay(hour: 8 + index, minute: 0),
    end: TimeOfDay(hour: 8 + index, minute: 45),
  );
  final String? id;
  final TextEditingController name;
  TimeOfDay start;
  TimeOfDay end;
  void dispose() => name.dispose();
}

class _TemplateEmptyState extends StatelessWidget {
  const _TemplateEmptyState();
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: const [
          Icon(Icons.schedule_outlined, size: 44, color: AppColors.cyan),
          SizedBox(height: 10),
          Text('还没有作息模板'),
          SizedBox(height: 4),
          Text(
            '新建一套节次时间，供学期和课程安排使用。',
            style: TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}

class _CurrentBadge extends StatelessWidget {
  const _CurrentBadge({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.blush,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 11, color: AppColors.primary),
    ),
  );
}
