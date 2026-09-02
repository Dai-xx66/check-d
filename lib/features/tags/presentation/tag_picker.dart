import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/tag_providers.dart';
import 'tags_page.dart';

class TagPicker extends ConsumerWidget {
  const TagPicker({required this.value, required this.onChanged, super.key});
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(tagsProvider)
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => TextButton(
            onPressed: () => ref.invalidate(tagsProvider),
            child: const Text('重新加载标签'),
          ),
          data: (tags) {
            final options = tags
                .where((t) => !t.archived || t.id == value)
                .toList();
            final selected = options.any((t) => t.id == value) ? value : null;
            return Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(selected),
                    initialValue: selected ?? '',
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '时间标签',
                      prefixIcon: Icon(Icons.label_outline),
                    ),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('其它')),
                      for (final tag in options)
                        DropdownMenuItem(
                          value: tag.id,
                          child: Row(
                            children: [
                              Icon(
                                Icons.circle,
                                color: Color(tag.colorValue),
                                size: 12,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${tag.name}${tag.archived ? '（已归档）' : ''}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (id) => onChanged(id == '' ? null : id),
                  ),
                ),
                IconButton(
                  tooltip: '管理标签',
                  icon: const Icon(Icons.label_important_outline),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const TagsPage()),
                  ),
                ),
              ],
            );
          },
        );
  }
}
