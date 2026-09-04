import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/database/database_provider.dart';
import 'package:ruleup/core/sync/sync_service.dart';
import 'package:ruleup/core/sync/sync_transport.dart';

final syncTransportProvider = Provider<SyncTransport>(
  (ref) => const DeferredSyncTransport(),
);

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    ref.watch(databaseProvider),
    ref.watch(syncTransportProvider),
  );
});

final syncControllerProvider = NotifierProvider<SyncController, SyncState>(
  SyncController.new,
);

class SyncController extends Notifier<SyncState> {
  @override
  SyncState build() => const SyncState();

  Future<void> syncPending(String userId) =>
      _sync(() => ref.read(syncServiceProvider).syncPending(userId));

  Future<void> retryFailed(String userId) =>
      _sync(() => ref.read(syncServiceProvider).retryFailed(userId));

  Future<void> _sync(Future<SyncResult> Function() action) async {
    state = const SyncState(status: SyncStatus.syncing);
    try {
      final result = await action();
      state = SyncState(
        status: result.failed == 0 ? SyncStatus.succeeded : SyncStatus.failed,
        processed: result.processed,
        failed: result.failed,
      );
    } on Object catch (error) {
      state = SyncState(status: SyncStatus.failed, message: error.toString());
    }
  }
}

enum SyncStatus { idle, syncing, succeeded, failed }

class SyncState {
  const SyncState({
    this.status = SyncStatus.idle,
    this.processed = 0,
    this.failed = 0,
    this.message,
  });

  final SyncStatus status;
  final int processed;
  final int failed;
  final String? message;
}
