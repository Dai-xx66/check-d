import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

enum NotificationPermissionState { unknown, granted, denied, unsupported }

abstract interface class NotificationPlatformService {
  Future<void> initialize();
  Future<bool> requestPermissions();
  Future<NotificationPermissionState> permissionState();
  Future<void> scheduleAt({
    required int id,
    required DateTime when,
    required String title,
    required String body,
  });
  Future<void> cancelAllPending();
}

class NotificationService implements NotificationPlatformService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
      windows: WindowsInitializationSettings(
        appName: 'Check D',
        appUserModelId: 'com.checkd.app',
        guid: '454d3d1c-51db-424d-8cab-904454b26ebc',
      ),
    );
    await _plugin.initialize(settings: settings);
    _initialized = true;
  }

  @override
  Future<bool> requestPermissions() async {
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final macos = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    final granted = await android?.requestNotificationsPermission();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
    await macos?.requestPermissions(alert: true, badge: true, sound: true);
    return granted ?? true;
  }

  @override
  Future<NotificationPermissionState> permissionState() async {
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      final enabled = await android.areNotificationsEnabled();
      return enabled == true
          ? NotificationPermissionState.granted
          : NotificationPermissionState.denied;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final macos = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    final settings =
        await ios?.checkPermissions() ?? await macos?.checkPermissions();
    if (settings != null) {
      return settings.isEnabled
          ? NotificationPermissionState.granted
          : NotificationPermissionState.denied;
    }
    return NotificationPermissionState.unsupported;
  }

  Future<void> showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    await initialize();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'task_reminders',
          '任务提醒',
          channelDescription: '周期任务和单次事项提醒',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> scheduleDaily({
    required int id,
    required int minuteOfDay,
    required String title,
    required String body,
  }) async {
    await initialize();
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      minuteOfDay ~/ 60,
      minuteOfDay % 60,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  @override
  Future<void> scheduleAt({
    required int id,
    required DateTime when,
    required String title,
    required String body,
  }) async {
    await initialize();
    if (!when.isAfter(DateTime.now())) return;
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// All scheduled notifications in this app are occurrence-based. Clearing
  /// them before a horizon rebuild guarantees a moved or cancelled occurrence
  /// cannot leave its previous notification behind.
  @override
  Future<void> cancelAllPending() async {
    await initialize();
    await _plugin.cancelAllPendingNotifications();
  }

  Future<void> scheduleWeekly({
    required int id,
    required int weekday,
    required int minuteOfDay,
    required String title,
    required String body,
  }) async {
    await initialize();
    final now = tz.TZDateTime.now(tz.local);
    var daysUntil = (weekday - now.weekday + 7) % 7;
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day + daysUntil,
      minuteOfDay ~/ 60,
      minuteOfDay % 60,
    );
    if (!scheduled.isAfter(now)) {
      daysUntil += 7;
      scheduled = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day + daysUntil,
        minuteOfDay ~/ 60,
        minuteOfDay % 60,
      );
    }
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  NotificationDetails get _details => const NotificationDetails(
    android: AndroidNotificationDetails(
      'task_reminders',
      '任务提醒',
      channelDescription: '周期任务和单次事项提醒',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );

  Future<void> cancel(int id) => _plugin.cancel(id: id);
}
