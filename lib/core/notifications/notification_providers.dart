import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notification_service.dart';

final notificationService = NotificationService();

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return notificationService;
});
