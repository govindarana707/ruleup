import 'package:drift/drift.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/database/tables/point_ledger.dart';
import 'package:ruleup/core/sync/sync_service.dart';
import 'package:ruleup/core/utils/habit_date.dart';

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
    return _getForSource(userId, PointLedgerSourceType.checkIn, checkInId);
  }

  Future<PointLedgerData?> getForMissedCheckIn(
    String userId,
    String habitId,
    DateTime habitDate,
  ) {
    return _getForSource(
      userId,
      PointLedgerSourceType.missedCheckIn,
      missedCheckInSourceId(habitId, habitDate),
    );
  }

  Future<PointLedgerData> createMissedCheckInPenalty({
    required String userId,
    required String habitId,
    required DateTime habitDate,
    required int points,
  }) => _database.transaction(() async {
    if (points > 0) {
      throw ArgumentError.value(points, 'points', 'Must be zero or negative');
    }
    final habit =
        await (_database.select(_database.habits)..where(
              (row) => row.id.equals(habitId) & row.userId.equals(userId),
            ))
            .getSingleOrNull();
    if (habit == null) throw ArgumentError.value(habitId, 'habitId');

    final sourceId = missedCheckInSourceId(habitId, habitDate);
    final existing = await _getForSource(
      userId,
      PointLedgerSourceType.missedCheckIn,
      sourceId,
    );
    if (existing != null) return existing;

    final created = await _database
        .into(_database.pointLedger)
        .insertReturningOrNull(
          PointLedgerCompanion.insert(
            userId: userId,
            sourceType: PointLedgerSourceType.missedCheckIn,
            sourceId: sourceId,
            points: points,
            reason: Value('Missed check-in on ${habitDateKey(habitDate)}'),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    if (created != null) {
      await _enqueue(created, 'create');
      return created;
    }
    return (await _getForSource(
      userId,
      PointLedgerSourceType.missedCheckIn,
      sourceId,
    ))!;
  });

  static String missedCheckInSourceId(String habitId, DateTime habitDate) {
    return '$habitId:${habitDateKey(habitDate)}';
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

  Future<PointLedgerData?> _getForSource(
    String userId,
    PointLedgerSourceType sourceType,
    String sourceId,
  ) {
    final storedType = const PointLedgerSourceTypeConverter().toSql(sourceType);
    final query = _database.select(_database.pointLedger)
      ..where(
        (row) =>
            row.userId.equals(userId) &
            row.sourceType.equals(storedType) &
            row.sourceId.equals(sourceId),
      );
    return query.getSingleOrNull();
  }
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
