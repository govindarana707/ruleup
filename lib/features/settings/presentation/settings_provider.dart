import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/database/database_provider.dart';
import 'package:ruleup/core/notifications/local_notification_service.dart';
import 'package:ruleup/core/notifications/local_notification_service_provider.dart';
import 'package:ruleup/core/sync/remote_change_merger.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/reminders/data/habit_reminder_repository_provider.dart';
import 'package:ruleup/features/reminders/data/habit_reminder_scheduler_provider.dart';
import 'package:ruleup/features/reminders/domain/habit_reminder_rescheduler.dart';

final settingsOverviewProvider =
    FutureProvider.family<SettingsOverview, String>((ref, userId) async {
      ref.watch(syncControllerProvider.select((state) => state.status));
      final database = ref.watch(databaseProvider);
      final queue =
          await (database.select(database.syncQueue)
                ..where((row) => row.userId.equals(userId))
                ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
              .get();
      final cursor =
          await (database.select(database.syncMetadata)..where(
                (row) =>
                    row.userId.equals(userId) &
                    row.key.equals(RemoteChangeMerger.cursorMetadataKey),
              ))
              .getSingleOrNull();
      final errors = queue
          .map((item) => item.lastError)
          .whereType<String>()
          .where((message) => message.trim().isNotEmpty)
          .map(_readableError)
          .toSet()
          .take(3)
          .toList(growable: false);
      return SettingsOverview(
        pendingCount: queue.length,
        failedCount: queue.where((item) => item.lastError != null).length,
        lastSuccessfulSync: cursor?.updatedAt,
        syncErrors: errors,
      );
    });

typedef SettingsLogoutAction = Future<void> Function();

final settingsLogoutActionProvider = Provider<SettingsLogoutAction>(
  (ref) => ref.read(authControllerProvider.notifier).logout,
);

typedef SettingsSyncAction = Future<void> Function(
  String userId, {
  required bool retry,
});

final settingsSyncActionProvider = Provider<SettingsSyncAction>(
  (ref) =>
      (userId, {required retry}) => retry
      ? ref.read(syncControllerProvider.notifier).retryFailed(userId)
      : ref.read(syncControllerProvider.notifier).synchronize(userId),
);

enum NotificationPermissionState {
  unknown,
  granted,
  denied,
  unavailable,
  error,
}

typedef NotificationPermissionAction =
    Future<NotificationPermissionState> Function();

final notificationPermissionActionProvider =
    Provider<NotificationPermissionAction>((ref) {
      final notifications = ref.watch(localNotificationServiceProvider);
      return () => _checkNotificationPermission(notifications);
    });

Future<NotificationPermissionState> _checkNotificationPermission(
  LocalNotificationService notifications,
) async {
  try {
    await notifications.initialize();
    return await notifications.requestPermission()
        ? NotificationPermissionState.granted
        : NotificationPermissionState.denied;
  } on UnsupportedError {
    return NotificationPermissionState.unavailable;
  } on Object {
    return NotificationPermissionState.error;
  }
}

typedef ReminderRefreshAction = Future<ReminderRefreshResult> Function(
  String userId,
);

final reminderRefreshActionProvider = Provider<ReminderRefreshAction>((ref) {
  final repository = ref.watch(habitReminderRepositoryProvider);
  final scheduler = ref.watch(habitReminderSchedulerProvider);
  return (userId) async {
    final reminders = await repository.list(userId);
    var scheduled = 0;
    var denied = false;
    var failed = false;
    for (final habitId in reminders.map((item) => item.habitId).toSet()) {
      final result = await scheduler.rescheduleHabit(userId, habitId);
      scheduled += result.scheduledCount;
      denied =
          denied || result.status == ReminderScheduleStatus.permissionDenied;
      failed = failed || result.status == ReminderScheduleStatus.failed;
    }
    return ReminderRefreshResult(
      reminderCount: reminders.length,
      scheduledCount: scheduled,
      permissionDenied: denied,
      failed: failed,
    );
  };
});

class SettingsOverview {
  const SettingsOverview({
    required this.pendingCount,
    required this.failedCount,
    required this.lastSuccessfulSync,
    this.syncErrors = const [],
  });

  final int pendingCount;
  final int failedCount;
  final DateTime? lastSuccessfulSync;
  final List<String> syncErrors;
}

class ReminderRefreshResult {
  const ReminderRefreshResult({
    required this.reminderCount,
    required this.scheduledCount,
    required this.permissionDenied,
    required this.failed,
  });

  final int reminderCount;
  final int scheduledCount;
  final bool permissionDenied;
  final bool failed;
}

String _readableError(String message) {
  final compact = message.replaceAll(RegExp(r'\s+'), ' ').trim();
  const limit = 180;
  return compact.length <= limit ? compact : '${compact.substring(0, limit)}…';
}
