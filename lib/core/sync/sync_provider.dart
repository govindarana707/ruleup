import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/database/database_provider.dart';
import 'package:ruleup/core/config/app_config.dart';
import 'package:ruleup/core/supabase/supabase_provider.dart';
import 'package:ruleup/core/sync/api_sync_transport.dart';
import 'package:ruleup/core/sync/supabase_habit_sync_data_source.dart';
import 'package:ruleup/core/sync/supabase_habit_sync_transport.dart';
import 'package:ruleup/core/sync/sync_service.dart';
import 'package:ruleup/core/sync/sync_transport.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/reminders/data/habit_reminder_scheduler_provider.dart';

final syncTransportProvider = Provider<SyncTransport>((ref) {
  final database = ref.watch(databaseProvider);
  return switch (AppConfig.habitSyncBackend) {
    HabitSyncBackend.cloudflare => ApiSyncTransport(
      database,
      ref.watch(apiClientProvider),
      ref.watch(tokenStorageProvider),
    ),
    HabitSyncBackend.supabase => SupabaseHabitSyncTransport(
      database,
      SupabaseHabitSyncDataSourceImpl(
        ref.watch(supabaseDatabaseServiceProvider) ??
            (throw StateError(
              'Supabase habit sync requires SUPABASE_URL and '
              'SUPABASE_ANON_KEY.',
            )),
      ),
    ),
  };
});

final syncServiceProvider = Provider<SyncService>((ref) {
  final reminderScheduler = ref.watch(habitReminderSchedulerProvider);
  return SyncService(
    ref.watch(databaseProvider),
    ref.watch(syncTransportProvider),
    onReminderChanges: (userId, habitIds) async {
      for (final habitId in habitIds) {
        await reminderScheduler.rescheduleHabit(userId, habitId);
      }
    },
  );
});

final syncControllerProvider = NotifierProvider<SyncController, SyncState>(
  SyncController.new,
);

typedef SyncLifecycleTrigger = Future<void> Function(String userId);

final syncLifecycleTriggerProvider = Provider<SyncLifecycleTrigger>(
  (ref) => ref.read(syncControllerProvider.notifier).synchronize,
);

class SyncController extends Notifier<SyncState> {
  @override
  SyncState build() => const SyncState();

  Future<void> synchronize(String userId) =>
      _sync(() => ref.read(syncServiceProvider).synchronize(userId));

  Future<void> retryFailed(String userId) => _sync(
    () =>
        ref.read(syncServiceProvider).synchronize(userId, retryFailures: true),
  );

  Future<void> _sync(Future<SyncResult> Function() action) async {
    state = const SyncState(status: SyncStatus.syncing);
    try {
      final result = await action();
      state = SyncState(
        status:
            result.failed == 0 &&
                !result.pendingProtected &&
                !result.dependencyDeferred
            ? SyncStatus.succeeded
            : SyncStatus.failed,
        processed: result.processed,
        failed: result.failed,
        pulled: result.pulled,
        pendingProtected: result.pendingProtected,
        message: result.pendingProtected || result.dependencyDeferred
            ? _safeSyncFailureMessage
            : null,
      );
    } on Object catch (error) {
      if (kDebugMode) debugPrint('RuleUp sync failed: $error');
      state = SyncState(
        status: SyncStatus.failed,
        message: _safeSyncFailureMessage,
      );
    }
  }
}

const _safeSyncFailureMessage = "Sync couldn't finish. Tap Retry.";

enum SyncStatus { idle, syncing, succeeded, failed }

class SyncState {
  const SyncState({
    this.status = SyncStatus.idle,
    this.processed = 0,
    this.failed = 0,
    this.pulled = 0,
    this.pendingProtected = false,
    this.message,
  });

  final SyncStatus status;
  final int processed;
  final int failed;
  final int pulled;
  final bool pendingProtected;
  final String? message;
}
