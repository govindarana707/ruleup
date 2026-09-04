import 'package:drift/drift.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/sync/sync_transport.dart';

class SyncService {
  SyncService(this._database, this._transport);

  final AppDatabase _database;
  final SyncTransport _transport;
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
      _run(userId, retryFailures: false);

  Future<SyncResult> retryFailed(String userId) =>
      _run(userId, retryFailures: true);

  Future<SyncResult> _run(String userId, {required bool retryFailures}) async {
    if (!_runningUsers.add(userId)) return const SyncResult();

    var succeeded = 0;
    var failed = 0;
    try {
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

      for (final item in items) {
        try {
          await _transport.send(item);
          await (_database.delete(_database.syncQueue)..where(
                (row) => row.id.equals(item.id) & row.userId.equals(userId),
              ))
              .go();
          succeeded++;
        } on Object catch (error) {
          final message = _boundedError(error);
          await (_database.update(_database.syncQueue)..where(
                (row) => row.id.equals(item.id) & row.userId.equals(userId),
              ))
              .write(
                SyncQueueCompanion(
                  attempts: Value(item.attempts + 1),
                  lastError: Value(message),
                  updatedAt: Value(DateTime.now().toUtc()),
                ),
              );
          failed++;
        }
      }
      return SyncResult(succeeded: succeeded, failed: failed);
    } finally {
      _runningUsers.remove(userId);
    }
  }

  String _boundedError(Object error) {
    final message = error.toString();
    return message.length <= 1000 ? message : message.substring(0, 1000);
  }
}

class SyncResult {
  const SyncResult({this.succeeded = 0, this.failed = 0});

  final int succeeded;
  final int failed;
  int get processed => succeeded + failed;
}
