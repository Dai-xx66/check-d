import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_providers.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/notifications/reminder_scheduler.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/agent_reminder_store.dart';
import '../domain/agent_models.dart';
import '../domain/agent_reminder_engine.dart';
import 'agent_providers.dart';

final agentRemindersAllowedProvider = Provider<bool>((ref) {
  final status = ref.watch(authControllerProvider).status;
  return status == AuthStatus.authenticated || status == AuthStatus.offline;
});

final agentReminderDataTriggerProvider = StreamProvider<int>((ref) {
  final database = ref.watch(appDatabaseProvider);
  var revision = 0;
  return database
      .customSelect(
        'SELECT 1 AS revision',
        readsFrom: {
          database.localTasks,
          database.longTermTaskRecords,
          database.taskScheduleRecords,
          database.oneTimeReminderRecords,
          database.taskCompletionRecords,
          database.courseRecords,
          database.courseScheduleRuleRecords,
          database.scheduleTemplateRecords,
          database.scheduleTemplateSegmentRecords,
          database.semesterRecords,
          database.dailyItemOverrideRecords,
          database.reminderRuleRecords,
        },
      )
      .watchSingle()
      .map((_) => ++revision);
});

final agentReminderContextProvider = FutureProvider<AgentContext>((ref) async {
  final owner = ref.watch(agentOwnerProvider);
  ref.watch(
    agentWorkspaceProvider.select(
      (value) => jsonEncode({
        'profile': value.value?.profile,
        'links': value.value?.taskLinks,
        'feedback': value.value?.feedback,
      }),
    ),
  );
  if (ref.read(agentWorkspaceProvider).value?.profile['remindersEnabled'] !=
          true ||
      !ref.watch(agentRemindersAllowedProvider)) {
    return AgentContext(
      ownerId: owner,
      revision: 'disabled',
      data: {
        'now': DateTime.now().toUtc().toIso8601String(),
        'profile': {'remindersEnabled': false},
      },
    );
  }
  ref.watch(agentReminderDataTriggerProvider);
  return ref.watch(agentRepositoryProvider).buildContext();
});

final agentReminderPermissionProvider =
    FutureProvider<NotificationPermissionState>((ref) async {
      try {
        return await ref.watch(notificationServiceProvider).permissionState();
      } on Object {
        return NotificationPermissionState.unsupported;
      }
    });

/// Called by the app's one scheduler after its common cancellation/rebuild.
final agentSupplementalReminderSourceProvider =
    Provider<SupplementalReminderSource>(
      (ref) => (now, through) async {
        if (!ref.read(agentRemindersAllowedProvider)) return const [];
        final owner = ref.read(agentOwnerProvider);
        final context = await ref.read(agentReminderContextProvider.future);
        if (!ref.mounted || !ref.read(agentOwnerGuardProvider)(owner)) {
          return const [];
        }
        return const AgentReminderEngine()
            .build(
              context,
              now: now,
              horizonDays: through.difference(now).inDays + 1,
            )
            .where(
              (item) => item.when.isAfter(now) && item.when.isBefore(through),
            )
            .map(
              (item) => SupplementalReminder(
                id: item.notificationId,
                when: item.when,
                title: item.title,
                body: item.body,
                atTimeOccurrenceId: item.occurrenceId,
              ),
            )
            .toList();
      },
    );

final agentForegroundReminderProvider =
    NotifierProvider<AgentForegroundReminderController, AgentReminder?>(
      AgentForegroundReminderController.new,
    );

class AgentForegroundReminderController extends Notifier<AgentReminder?> {
  var _checking = false;
  @override
  AgentReminder? build() {
    ref.watch(agentOwnerProvider);
    ref.watch(agentRemindersAllowedProvider);
    return null;
  }

  void dismiss() => state = null;

  Future<void> checkNow({DateTime? now}) async {
    if (_checking || !ref.read(agentRemindersAllowedProvider)) return;
    final current = now ?? DateTime.now();
    if (state != null) {
      if (state!.isDue(current)) return;
      state = null;
    }
    _checking = true;
    final owner = ref.read(agentOwnerProvider);
    final guard = ref.read(agentOwnerGuardProvider);
    try {
      var context = await ref.read(agentReminderContextProvider.future);
      final storedDay = DateTime.tryParse('${context.data['now']}');
      if (storedDay != null &&
          _dayKey(AgentReminderEngine.beijingWallTime(storedDay)) !=
              _dayKey(AgentReminderEngine.beijingWallTime(current))) {
        ref.invalidate(agentReminderContextProvider);
        context = await ref.read(agentReminderContextProvider.future);
      }
      if (!ref.mounted || !guard(owner)) return;
      final due = const AgentReminderEngine()
          .build(context, now: current)
          .where((item) => item.isDue(current));
      final store = AgentReminderStore(ref.read(appDatabaseProvider));
      for (final item in due) {
        if (await store.claimDisplayed(
          owner,
          item.key,
          () => ref.mounted && guard(owner),
        )) {
          if (ref.mounted && guard(owner)) state = item;
          break;
        }
      }
    } on Object {
      // Keep the app usable while local data restores or an account changes.
    } finally {
      _checking = false;
    }
  }

  String _dayKey(DateTime day) => '${day.year}-${day.month}-${day.day}';
}
