import 'package:drift/drift.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/sync/remote_change_merger.dart';
import 'package:ruleup/core/sync/sync_retention_pruner.dart';
import 'package:ruleup/core/sync/sync_transport.dart';

class SyncService {
  SyncService(
    this._database,
    this._transport, {
    RemoteChangeMerger? merger,
    SyncRetentionPruner? retentionPruner,
    this.onReminderChanges,
  }) : _merger = merger ?? RemoteChangeMerger(_database),
       _retentionPruner = retentionPruner ?? SyncRetentionPruner(_database);

  final AppDatabase _database;
  final SyncTransport _transport;
  final RemoteChangeMerger _merger;
  final SyncRetentionPruner _retentionPruner;
  final Future<void> Function(String userId, Set<String> habitIds)?
  onReminderChanges;
  final Set<String> _runningUsers = {};

  Future<void> enqueue({
    required String userId,
    required String entityType,
    required String entityId,
    required String operation,
  }) async {
    await _database.enqueueSyncOperation(
      SyncQueueCompanion.insert(
        userId: userId,
        entityType: entityType,
        entityId: entityId,
        operation: operation,
      ),
    );
  }

  Future<SyncResult> syncPending(String userId) =>
      _withUserLock(userId, () => _push(userId, retryFailures: false));

  Future<SyncResult> retryFailed(String userId) =>
      _withUserLock(userId, () => _push(userId, retryFailures: true));

  Future<SyncResult> synchronize(String userId, {bool retryFailures = false}) =>
      _withUserLock(userId, () async {
        var result = await _push(userId, retryFailures: false);
        if (retryFailures) {
          result = result + await _push(userId, retryFailures: true);
        }
        result = result + await _pull(userId);
        try {
          await _retentionPruner.prune(userId);
        } on Object {
          // Retention is best-effort and must not turn completed sync into a
          // data failure. Eligible rows remain safe to retry next time.
        }
        return result;
      });

  Future<SyncResult> _withUserLock(
    String userId,
    Future<SyncResult> Function() action,
  ) async {
    if (!_runningUsers.add(userId)) return const SyncResult();
    try {
      return await action();
    } finally {
      _runningUsers.remove(userId);
    }
  }

  Future<SyncResult> _push(String userId, {required bool retryFailures}) async {
    var succeeded = 0;
    var failed = 0;
    final query = _database.select(_database.syncQueue)
      ..where(
        (row) =>
            row.userId.equals(userId) &
            (retryFailures
                ? row.attempts.isBiggerThanValue(0)
                : row.attempts.equals(0)),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]);
    final items = await query.get();

    final transport = _transport;
    final eligibleItems = <SyncQueueData>[];
    for (final item in items) {
      if (transport is ItemScopedSyncTransport) {
        if (await transport.supportsItem(item)) eligibleItems.add(item);
      } else if (transport is! ScopedSyncTransport ||
          transport.supports(item.entityType)) {
        eligibleItems.add(item);
      }
    }
    eligibleItems.sort((left, right) {
      final dependency = _dependencyOrder(left.entityType)
          .compareTo(_dependencyOrder(right.entityType));
      if (dependency != 0) return dependency;
      return left.createdAt.compareTo(right.createdAt);
    });

    for (final item in eligibleItems) {
      try {
        await _transport.send(item);
        await (_database.delete(_database.syncQueue)..where(
              (row) => row.id.equals(item.id) & row.userId.equals(userId),
            ))
            .go();
        succeeded++;
      } on Object catch (error) {
        final message = _boundedError(error);
        final attempts = error is ClassifiedSyncFailure && !error.retryable
            ? -1
            : item.attempts + 1;
        await (_database.update(_database.syncQueue)..where(
              (row) => row.id.equals(item.id) & row.userId.equals(userId),
            ))
            .write(
              SyncQueueCompanion(
                attempts: Value(attempts),
                lastError: Value(message),
                updatedAt: Value(DateTime.now().toUtc()),
              ),
            );
        failed++;
      }
    }
    return SyncResult(succeeded: succeeded, failed: failed);
  }

  Future<SyncResult> _pull(String userId) async {
    final transport = _transport;
    if (transport is! PullSyncTransport) return const SyncResult();

    final cursorKey = transport is CursorScopedPullSyncTransport
        ? transport.cursorMetadataKey
        : RemoteChangeMerger.cursorMetadataKey;
    var cursor = await _merger.readCursor(userId, key: cursorKey);
    var pulled = 0;
    var pendingProtected = false;
    for (var page = 0; page < 20; page++) {
      final batch = transport is UserScopedPullSyncTransport
          ? await transport.pullForUser(userId, cursor)
          : await transport.pull(cursor);
      final merged = await _merger.apply(
        userId,
        cursor,
        batch,
        cursorKey: cursorKey,
      );
      cursor = merged.cursor;
      pulled += merged.merged;
      pendingProtected = merged.blockedByPendingLocalChange;
      await _refreshReminders(userId, merged.reminderHabitIds);
      if (pendingProtected || !batch.hasMore) {
        return SyncResult(pulled: pulled, pendingProtected: pendingProtected);
      }
    }
    throw StateError('Pull sync exceeded the 20-page safety limit.');
  }

  Future<void> _refreshReminders(String userId, Set<String> habitIds) async {
    if (habitIds.isEmpty || onReminderChanges == null) return;
    try {
      await onReminderChanges!(userId, habitIds);
    } on Object {
      // Notification failures never make data synchronization fail.
    }
  }

  String _boundedError(Object error) {
    final message = error.toString();
    return message.length <= 1000 ? message : message.substring(0, 1000);
  }

  int _dependencyOrder(String entityType) => switch (entityType) {
    'category' => 0,
    'habit' => 1,
    'habit_option' => 2,
    'habit_schedule' => 3,
    'point_rule' => 4,
    'habit_pause' => 5,
    'habit_reminder' => 6,
    'reward_image_upload' => 7,
    'reward' => 8,
    'check_in' => 9,
    'point_ledger' => 10,
    'reward_image_delete' => 11,
    _ => 100,
  };
}

class SyncResult {
  const SyncResult({
    this.succeeded = 0,
    this.failed = 0,
    this.pulled = 0,
    this.pendingProtected = false,
  });

  final int succeeded;
  final int failed;
  final int pulled;
  final bool pendingProtected;
  int get processed => succeeded + failed + pulled;

  SyncResult operator +(SyncResult other) => SyncResult(
    succeeded: succeeded + other.succeeded,
    failed: failed + other.failed,
    pulled: pulled + other.pulled,
    pendingProtected: pendingProtected || other.pendingProtected,
  );
}
