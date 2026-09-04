import 'package:flutter/foundation.dart';

class PlatformCapabilities {
  const PlatformCapabilities({
    required this.systemNotifications,
    required this.inAppReminderDialog,
    required this.alarmSound,
    required this.lockScreenLiveActivity,
    required this.dynamicIsland,
    required this.desktopMiniWindow,
  });

  final bool systemNotifications;
  final bool inAppReminderDialog;
  final bool alarmSound;
  final bool lockScreenLiveActivity;
  final bool dynamicIsland;
  final bool desktopMiniWindow;

  static PlatformCapabilities current() {
    final platform = defaultTargetPlatform;
    final isMobile =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    final isDesktop =
        platform == TargetPlatform.macOS || platform == TargetPlatform.windows;
    if (kIsWeb) {
      return const PlatformCapabilities(
        systemNotifications: false,
        inAppReminderDialog: true,
        alarmSound: false,
        lockScreenLiveActivity: false,
        dynamicIsland: false,
        desktopMiniWindow: false,
      );
    }
    return PlatformCapabilities(
      systemNotifications: isMobile || isDesktop,
      inAppReminderDialog: true,
      alarmSound: isMobile || isDesktop,
      lockScreenLiveActivity: platform == TargetPlatform.iOS,
      dynamicIsland: platform == TargetPlatform.iOS,
      desktopMiniWindow: isDesktop,
    );
  }
}

abstract interface class AlarmService {
  Future<void> scheduleAlarm({
    required int id,
    required DateTime when,
    required String title,
    required String body,
  });

  Future<void> cancelAlarm(int id);
}

abstract interface class CourseLiveStatusService {
  Future<void> startCourseActivity(String courseId);

  Future<void> stopCourseActivity(String courseId);
}

abstract interface class DesktopMiniWindowService {
  Future<void> showMiniWindow();

  Future<void> hideMiniWindow();
}
