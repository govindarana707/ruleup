import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/notifications/local_notification_service.dart';

final localNotificationServiceProvider = Provider<LocalNotificationService>((
  ref,
) {
  return AndroidLocalNotificationService();
});
