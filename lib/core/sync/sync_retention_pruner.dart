import 'package:drift/drift.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/database/tables/point_ledger.dart';

class SyncRetentionPruner {
  SyncRetentionPruner(
    this._database, {
    this.retention = const Duration(days: 30),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AppDatabase _database;
  final Duration retention;
  final DateTime Function() _now;

  Future<SyncPruneResult> prune(String userId) =>
      _database.transaction(() async {
        final cutoff = _now().toUtc().subtract(retention);
        final queued = await (_database.select(
          _database.syncQueue,
        )..where((row) => row.userId.equals(userId))).get();
        final queuedImageIds = queued
            .where(
              (row) =>
                  row.entityType == 'reward_image_upload' ||
                  row.entityType == 'reward_image_delete',
            )
            .map((row) => row.entityId)
            .toSet();
        final queuedRedemptionIds = queued
            .where((row) => row.entityType == 'reward_redemption')
            .map((row) => row.entityId)
            .toSet();

        final completedImages =
            await (_database.select(_database.rewardImageOperations)..where(
                  (row) =>
                      row.userId.equals(userId) &
                      row.completed.equals(true) &
                      row.updatedAt.isSmallerThanValue(cutoff),
                ))
                .get();
        final imageIds = completedImages
            .where((row) => !queuedImageIds.contains(row.id))
            .map((row) => row.id)
            .toList(growable: false);
        final deletedImages = imageIds.isEmpty
            ? 0
            : await (_database.delete(
                _database.rewardImageOperations,
              )..where((row) => row.id.isIn(imageIds))).go();

        final completedRequests =
            await (_database.select(_database.rewardRedemptionRequests)..where(
                  (row) =>
                      row.userId.equals(userId) &
                      row.status.equals('completed') &
                      row.updatedAt.isSmallerThanValue(cutoff),
                ))
                .get();
        final redemptionIds = <String>[];
        final storedType = const PointLedgerSourceTypeConverter().toSql(
          PointLedgerSourceType.rewardRedemption,
        );
        for (final request in completedRequests) {
          if (queuedRedemptionIds.contains(request.id)) continue;
          final ledger =
              await (_database.select(_database.pointLedger)..where(
                    (row) =>
                        row.id.equals(request.ledgerId) &
                        row.userId.equals(userId) &
                        row.sourceType.equals(storedType) &
                        row.sourceId.equals(request.id),
                  ))
                  .getSingleOrNull();
          if (ledger != null) redemptionIds.add(request.id);
        }
        final deletedRequests = redemptionIds.isEmpty
            ? 0
            : await (_database.delete(
                _database.rewardRedemptionRequests,
              )..where((row) => row.id.isIn(redemptionIds))).go();

        return SyncPruneResult(
          rewardImageOperations: deletedImages,
          rewardRedemptionRequests: deletedRequests,
        );
      });
}

class SyncPruneResult {
  const SyncPruneResult({
    required this.rewardImageOperations,
    required this.rewardRedemptionRequests,
  });

  final int rewardImageOperations;
  final int rewardRedemptionRequests;
}
