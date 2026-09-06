import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/database/database_provider.dart';
import 'package:ruleup/core/notifications/local_notification_service_provider.dart';
import 'package:ruleup/features/reminders/data/habit_reminder_scheduler.dart';

final habitReminderSchedulerProvider = Provider<HabitReminderScheduler>((ref) {
  return HabitReminderScheduler(
    ref.watch(databaseProvider),
    ref.watch(localNotificationServiceProvider),
  );
});
