import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import '../notifications/reminder_scheduler_providers.dart';
import '../../features/auth/presentation/auth_controller.dart';
import 'sync_providers.dart';

/// Keeps upload-only sync responsive to login, outbox writes, retry ticks, and
/// app resume without changing any local-first business operation.
class SyncUploadHost extends ConsumerStatefulWidget {
  const SyncUploadHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SyncUploadHost> createState() => _SyncUploadHostState();
}

class _SyncUploadHostState extends ConsumerState<SyncUploadHost>
    with WidgetsBindingObserver {
  ProviderSubscription<AuthState>? _authSubscription;
  bool _authSyncScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSubscription = ref.listenManual<AuthState>(
      authControllerProvider,
      (_, _) => _scheduleAuthSync(),
      fireImmediately: true,
    );
  }

  void _scheduleAuthSync() {
    if (_authSyncScheduled) return;
    _authSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authSyncScheduled = false;
      if (!mounted) return;
      unawaited(_syncFor(ref.read(authControllerProvider)));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_reconcileOnResume());
    }
  }

  Future<void> _syncFor(AuthState state) async {
    final account = ref.read(syncAccountCoordinatorProvider);
    final userId = ref.read(supabaseClientProvider)?.auth.currentUser?.id;
    if (state.status != AuthStatus.authenticated ||
        userId == null ||
        state.userId != userId) {
      account?.signedOut();
      return;
    }

    final result = await account?.onAuthenticated(userId);
    if (result?.succeeded ?? false) {
      await ref
          .read(reminderSchedulerProvider)
          .refreshFuture()
          .catchError((_) {});
    }
  }

  Future<void> _reconcileOnResume() async {
    final userId = ref.read(supabaseClientProvider)?.auth.currentUser?.id;
    final auth = ref.read(authControllerProvider);
    if (userId == null ||
        auth.status != AuthStatus.authenticated ||
        auth.userId != userId) {
      ref.read(syncAccountCoordinatorProvider)?.signedOut();
      return;
    }
    final result = await ref
        .read(syncAccountCoordinatorProvider)
        ?.onAppResumed(userId);
    if (result?.succeeded ?? false) {
      await ref
          .read(reminderSchedulerProvider)
          .refreshFuture()
          .catchError((_) {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
