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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSubscription = ref.listenManual<AuthState>(
      authControllerProvider,
      (_, state) => _syncFor(state),
      fireImmediately: true,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_reconcileOnResume());
    }
  }

  Future<void> _syncFor(AuthState state) async {
    final upload = ref.read(syncUploadCoordinatorProvider);
    final userId = ref.read(supabaseClientProvider)?.auth.currentUser?.id;
    if (state.status != AuthStatus.authenticated || userId == null) {
      upload?.setActive(false, null);
      return;
    }

    final restored = await ref
        .read(syncDownloadCoordinatorProvider)
        ?.onAuthenticated(userId);
    if (restored?.succeeded ?? false) {
      await ref
          .read(reminderSchedulerProvider)
          .refreshFuture()
          .catchError((_) {});
    }
    upload?.setActive(true, userId);
  }

  Future<void> _reconcileOnResume() async {
    final restored = await ref
        .read(syncDownloadCoordinatorProvider)
        ?.onAppResumed();
    if (restored?.succeeded ?? false) {
      await ref
          .read(reminderSchedulerProvider)
          .refreshFuture()
          .catchError((_) {});
    }
    ref.read(syncUploadCoordinatorProvider)?.onAppResumed();
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
