import 'package:drift/drift.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/database/tables/point_ledger.dart';
import 'package:ruleup/core/sync/sync_service.dart';

class PointLedgerRepository {
  PointLedgerRepository(this._database, this._sync);

  final AppDatabase _database;
  final SyncService _sync;

  Future<PointLedgerData> reconcileCheckIn({
    required String userId,
    required String checkInId,
  }) => _database.transaction(() async {
    final checkIn =
        await (_database.select(_database.checkIns)..where(
              (row) => row.id.equals(checkInId) & row.userId.equals(userId),
            ))
            .getSingleOrNull();
    if (checkIn == null) throw ArgumentError.value(checkInId, 'checkInId');

    final existing = await getForCheckIn(userId, checkInId);
    if (existing == null) {
      final created = await _database
          .into(_database.pointLedger)
          .insertReturning(
            PointLedgerCompanion.insert(
              userId: userId,
              sourceType: PointLedgerSourceType.checkIn,
              sourceId: checkInId,
              points: checkIn.awardedPoints,
            ),
          );
      await _enqueue(created, 'create');
      return created;
    }
    if (existing.points == checkIn.awardedPoints) return existing;

    await (_database.update(_database.pointLedger)..where(
          (row) => row.id.equals(existing.id) & row.userId.equals(userId),
        ))
        .write(PointLedgerCompanion(points: Value(checkIn.awardedPoints)));
    final reconciled = await getForCheckIn(userId, checkInId);
    await _enqueue(reconciled!, 'update');
    return reconciled;
  });

  Future<PointLedgerData?> getForCheckIn(String userId, String checkInId) {
    final query = _database.select(_database.pointLedger)
      ..where(
        (row) =>
            row.userId.equals(userId) &
            row.sourceType.equals(
              const PointLedgerSourceTypeConverter().toSql(
                PointLedgerSourceType.checkIn,
              ),
            ) &
            row.sourceId.equals(checkInId),
      );
    return query.getSingleOrNull();
  }

  Future<WalletTotals> getWallet(String userId) async {
    final entries = await (_database.select(
      _database.pointLedger,
    )..where((row) => row.userId.equals(userId))).get();
    var availablePoints = 0;
    var lifetimeEarned = 0;
    var spentPoints = 0;

    for (final entry in entries) {
      availablePoints += entry.points;
      if (entry.points > 0) lifetimeEarned += entry.points;
      if (entry.points < 0 && entry.sourceType.isRedemption) {
        spentPoints += entry.points.abs();
      }
    }
    return WalletTotals(
      availablePoints: availablePoints,
      lifetimeEarned: lifetimeEarned,
      spentPoints: spentPoints,
    );
  }

  Future<void> _enqueue(PointLedgerData entry, String operation) =>
      _sync.enqueue(
        userId: entry.userId,
        entityType: 'point_ledger',
        entityId: entry.id,
        operation: operation,
      );
}

class WalletTotals {
  const WalletTotals({
    required this.availablePoints,
    required this.lifetimeEarned,
    required this.spentPoints,
  });

  final int availablePoints;
  final int lifetimeEarned;
  final int spentPoints;
}
