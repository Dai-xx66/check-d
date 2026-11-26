import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/check_d_design.dart';
import '../application/agent_reminder_providers.dart';

/// Foreground only: background delivery is handled by the unified scheduler.
class AgentReminderHost extends ConsumerStatefulWidget {
  const AgentReminderHost({required this.child, this.onOpen, super.key});
  final Widget child;
  final void Function(String request)? onOpen;
  @override
  ConsumerState<AgentReminderHost> createState() => _AgentReminderHostState();
}

class _AgentReminderHostState extends ConsumerState<AgentReminderHost>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _active = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual(agentReminderContextProvider, (_, _) => _check());
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (mounted && _active) {
      ref.read(agentForegroundReminderProvider.notifier).checkNow();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) {
      ref.invalidate(agentReminderContextProvider);
      _check();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reminder = ref.watch(agentForegroundReminderProvider);
    return Stack(
      children: [
        widget.child,
        if (reminder != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Material(
                      color: Colors.transparent,
                      child: CheckDSurface(
                        level: CheckDSurfaceLevel.glassActive,
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.notifications_active_outlined,
                              color: AppColors.primaryStrong,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    reminder.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(reminder.body),
                                  const SizedBox(height: 5),
                                  Text(
                                    '可在“我的 → CheckD 智能体”反馈；关闭提示不代表已读或完成。',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                  if (widget.onOpen != null)
                                    TextButton(
                                      onPressed: () {
                                        ref
                                            .read(
                                              agentForegroundReminderProvider
                                                  .notifier,
                                            )
                                            .dismiss();
                                        widget.onOpen!(reminder.request);
                                      },
                                      child: const Text('打开智能体'),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: '关闭这条提示',
                              onPressed: () => ref
                                  .read(
                                    agentForegroundReminderProvider.notifier,
                                  )
                                  .dismiss(),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
