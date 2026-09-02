import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../tasks/presentation/task_color_picker.dart';
import '../application/tag_providers.dart';

class TagsPage extends ConsumerWidget {
  const TagsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: const Text('标签管理'),
      actions: [
        IconButton(
          tooltip: '新建标签',
          onPressed: () => _edit(context, ref),
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    body: ref
        .watch(tagsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: TextButton(
              onPressed: () => ref.invalidate(tagsProvider),
              child: const Text('加载失败，重试'),
            ),
          ),
          data: (tags) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const ListTile(
                    leading: Icon(Icons.label, color: Color(0xFF8793A6)),
                    title: Text('其它'),
                    trailing: Icon(Icons.lock_outline, size: 18),
                  ),
                  for (final tag in [
                    ...tags.where((t) => !t.archived),
                    ...tags.where((t) => t.archived),
                  ])
                    ListTile(
                      leading: Icon(Icons.label, color: Color(tag.colorValue)),
                      title: Text(tag.name),
                      subtitle: tag.archived ? const Text('已归档') : null,
                      onTap: () => _edit(context, ref, tag),
                      trailing: IconButton(
                        tooltip: tag.archived ? '恢复标签' : '归档标签',
                        icon: Icon(
                          tag.archived
                              ? Icons.unarchive_outlined
                              : Icons.archive_outlined,
                        ),
                        onPressed: () async {
                          final confirmed =
                              tag.archived ||
                              await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('归档标签？'),
                                      content: const Text('已有任务和计时历史会保留此标签。'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: const Text('取消'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: const Text('归档'),
                                        ),
                                      ],
                                    ),
                                  ) ==
                                  true;
                          if (!confirmed) return;
                          try {
                            await ref
                                .read(tagRepositoryProvider)
                                .setArchived(tag.id, !tag.archived);
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('操作失败，请重试')),
                              );
                            }
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
  );

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    TagRecord? tag,
  ]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _TagEditor(tag: tag),
    );
  }
}

class _TagEditor extends ConsumerStatefulWidget {
  const _TagEditor({this.tag});
  final TagRecord? tag;
  @override
  ConsumerState<_TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends ConsumerState<_TagEditor> {
  late final _name = TextEditingController(text: widget.tag?.name ?? '');
  late int _color = widget.tag?.colorValue ?? taskColorValues.first;
  String? _error;
  bool _saving = false;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.tag == null ? '新建标签' : '编辑标签'),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              maxLength: 30,
              autofocus: true,
              decoration: InputDecoration(labelText: '标签名称', errorText: _error),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final color in taskColorValues)
                  IconButton(
                    tooltip: '选择颜色 ${taskColorValues.indexOf(color) + 1}',
                    onPressed: _saving
                        ? null
                        : () => setState(() => _color = color),
                    icon: Icon(
                      _color == color ? Icons.check_circle : Icons.circle,
                      color: Color(color),
                      size: 30,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _saving
            ? null
            : () async {
                setState(() {
                  _saving = true;
                  _error = null;
                });
                try {
                  await ref
                      .read(tagRepositoryProvider)
                      .save(
                        id: widget.tag?.id,
                        name: _name.text,
                        colorValue: _color,
                      );
                  if (context.mounted) Navigator.pop(context);
                } catch (error) {
                  if (mounted) {
                    setState(() {
                      _saving = false;
                      _error = error is ArgumentError
                          ? '${error.message}'
                          : '保存失败，请重试';
                    });
                  }
                }
              },
        child: Text(_saving ? '保存中' : '保存'),
      ),
    ],
  );
}
