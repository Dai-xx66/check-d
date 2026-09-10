import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../mini_window/data/mini_window_repository.dart';
import '../domain/lock_screen_status_snapshot.dart';

class LockScreenStatusService {
  LockScreenStatusService({
    required MiniWindowRepository repository,
    required NotificationPlatformService notifications,
  }) : _repository = repository,
       _notifications = notifications;

  static const _channel = MethodChannel('check_d/lock_screen_status');

  final MiniWindowRepository _repository;
  final NotificationPlatformService _notifications;

  Future<LockScreenStatusSnapshot?> refresh({DateTime? now}) async {
    if (kIsWeb) return null;
    final capabilities = PlatformCapabilities.current();
    if (!capabilities.lockScreenLiveActivity &&
        !capabilities.systemNotifications) {
      return null;
    }

    try {
      // Android's ongoing status is a notification. Do not ask for permission
      // here; Settings remains the single permission entry point.
      if (defaultTargetPlatform == TargetPlatform.android) {
        final permission = await _notifications.permissionState();
        if (permission != NotificationPermissionState.granted) return null;
      }
      final snapshot = LockScreenStatusSnapshot.fromMiniWindow(
        await _repository.load(now: now),
      );
      await _channel.invokeMethod<void>('sync', {
        'json': jsonEncode(snapshot.toJson()),
      });
      return snapshot;
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      debugPrint(
        '[LockScreenStatus] sync failed: ${error.code} ${error.message}',
      );
      return null;
    } on Error {
      // Widget tests do not register platform notification implementations.
      // Lock-screen status is auxiliary, so an unavailable bridge is silent.
      return null;
    } on Object catch (error) {
      debugPrint('[LockScreenStatus] sync failed: $error');
      return null;
    }
  }
}
