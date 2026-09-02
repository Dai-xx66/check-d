import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/empty_state.dart';
import '../application/task_providers.dart';
import '../domain/task_models.dart';
import 'task_detail_page.dart';
import 'task_icon_picker.dart';

class TaskListPage extends ConsumerStatefulWidget {
  const TaskListPage({super.key});

  @override
  ConsumerState<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends ConsumerState<TaskListPage> {
  TaskLifecycle _status = TaskLifecycle.active;

  @override
  Widget build(BuildContext context) {
    final tasksValue = ref.watch(tasksByStatusProvider(_status));
    return Scaffold(
      appBar: AppBar(
        title: const Text('全部任务'),
        backgroundColor: AppColors.background,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: SegmentedButton<TaskLifecycle>(
                    segments: const [
                      ButtonSegment(
                        value: TaskLifecycle.active,
                        icon: Icon(Icons.play_circle_outline_rounded),
                        label: Text('全部'),
                      ),
                      ButtonSegment(
                        value: TaskLifecycle.archived,
                        icon: Icon(Icons.archive_outlined),
                        label: Text('已归档'),
                      ),
                    ],
                    selected: {_status},
                    onSelectionChanged: (selection) =>
                        setState(() => _status = selection.first),
                  ),
                ),
                Expanded(
                  child: tasksValue.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, stackTrace) =>
                        const Center(child: Text('任务加载失败')),
                    data: (tasks) => tasks.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                            children: [
                              EmptyState(
                                icon: _status == TaskLifecycle.active
                                    ? Icons.checklist_rounded
                                    : Icons.archive_outlined,
                                title: _status == TaskLifecycle.active
                                    ? '还没有任务'
                                    : '没有归档任务',
                                message: _status == TaskLifecycle.active
                                    ? '通过中央添加入口创建长期任务或单次事项提醒。'
                                    : '归档后的任务会保留在这里。',
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                            itemCount: tasks.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) =>
                                _TaskListTile(task: tasks[index]),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskListTile extends StatelessWidget {
  const _TaskListTile({required this.task});

  final TaskDetails task;

  @override
  Widget build(BuildContext context) {
    final color = Color(task.colorValue);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        minTileHeight: 74,
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(taskIconData(task.iconName), color: color),
        ),
        title: Text(
          task.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(_subtitle(task)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (context) => TaskDetailPage(taskId: task.id),
          ),
        ),
      ),
    );
  }

  String _subtitle(TaskDetails task) {
    if (task.kind == TaskKind.oneTime) {
      final mode = task.hasTimer ? '计时事项' : '普通事项';
      return '$mode · ${DateFormat('M月d日 HH:mm').format(task.scheduledAt!)}';
    }
    final mode = switch (task.checkMode) {
      LongTermCheckMode.freeTimer => '自由计时',
      LongTermCheckMode.targetTimer => '目标计时',
      _ => '点击完成',
    };
    return '长期任务 · $mode';
  }
}
