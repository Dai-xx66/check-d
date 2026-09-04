import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/day_schedule_providers.dart';

class AdHocTimerFormPage extends ConsumerStatefulWidget {
  const AdHocTimerFormPage({super.key});

  @override
  ConsumerState<AdHocTimerFormPage> createState() => _AdHocTimerFormPageState();
}

class _AdHocTimerFormPageState extends ConsumerState<AdHocTimerFormPage> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('新建临时计时')),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: '计时名称 *'),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: const Text('创建计时'),
          ),
        ],
      ),
    ),
  );

  Future<void> _save() async {
    if (_controller.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请填写计时名称')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(dayScheduleRepositoryProvider)
          .createAdHocTimer(title: _controller.text);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
