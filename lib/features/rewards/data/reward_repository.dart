import 'package:drift/drift.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/database/database_uuid.dart';
import 'package:ruleup/core/database/tables/point_ledger.dart';
import 'package:ruleup/core/sync/sync_service.dart';

class RewardRepository {
  RewardRepository(
    this._database,
    this._sync, {
    this.authoritativeRemoteRedemption = false,
  });

  final AppDatabase _database;
  final SyncService _sync;
  final bool authoritativeRemoteRedemption;

  Future<Reward> create({
    required String userId,
    required String name,
    required int pointsCost,
    double? monetaryCap,
    int sortOrder = 0,
  }) => _database.transaction(() async {
    _validate(pointsCost: pointsCost, monetaryCap: monetaryCap);
    final reward = await _database
        .into(_database.rewards)
        .insertReturning(
          RewardsCompanion.insert(
            userId: userId,
            name: _validName(name),
            pointsCost: pointsCost,
            monetaryCap: Value(monetaryCap),
            sortOrder: Value(sortOrder),
          ),
        );
    await _enqueueReward(reward, 'create');
    return reward;
  });

  Future<Reward?> getById(String userId, String id) {
    final query = _database.select(_database.rewards)
      ..where((row) => row.id.equals(id) & row.userId.equals(userId));
    return query.getSingleOrNull();
  }

  Future<List<Reward>> list(String userId, {bool includeArchived = false}) {
    final query = _database.select(_database.rewards)
      ..where(
        (row) =>
            row.userId.equals(userId) &
            (includeArchived ? const Constant(true) : row.archivedAt.isNull()),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.sortOrder),
        (row) => OrderingTerm.asc(row.name),
        (row) => OrderingTerm.asc(row.createdAt),
      ]);
    return query.get();
  }

  Future<Reward?> update({
    required String userId,
    required String id,
    required String name,
    required int pointsCost,
    required double? monetaryCap,
    required int sortOrder,
  }) => _database.transaction(() async {
    final existing = await getById(userId, id);
    if (existing == null) return null;
    _validate(pointsCost: pointsCost, monetaryCap: monetaryCap);
    await (_database.update(
      _database.rewards,
    )..where((row) => row.id.equals(id) & row.userId.equals(userId))).write(
      RewardsCompanion(
        name: Value(_validName(name)),
        pointsCost: Value(pointsCost),
        monetaryCap: Value(monetaryCap),
        sortOrder: Value(sortOrder),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
    final updated = await getById(userId, id);
    await _enqueueReward(updated!, 'update');
    return updated;
  });

  Future<bool> archive(String userId, String id) =>
      _database.transaction(() async {
        final existing = await getById(userId, id);
        if (existing == null) return false;
        if (existing.archivedAt != null) return true;
        final now = DateTime.now().toUtc();
        await (_database.update(
          _database.rewards,
        )..where((row) => row.id.equals(id) & row.userId.equals(userId))).write(
          RewardsCompanion(archivedAt: Value(now), updatedAt: Value(now)),
        );
        await _enqueueReward(existing, 'archive');
        return true;
      });

  Future<bool> restore(String userId, String id) => _database.transaction(
    () async {
      final existing = await getById(userId, id);
      if (existing == null) return false;
      if (existing.archivedAt == null) return true;
      final now = DateTime.now().toUtc();
      await (_database.update(
        _database.rewards,
      )..where((row) => row.id.equals(id) & row.userId.equals(userId))).write(
        RewardsCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
      );
      final updated = await getById(userId, id);
      await _enqueueReward(updated!, 'update');
      return true;
    },
  );

  Future<Reward?> setImageKey(String userId, String id, String? imageKey) =>
      _database.transaction(() async {
        final existing = await getById(userId, id);
        if (existing == null) return null;
        final now = DateTime.now().toUtc();
        await (_database.update(
          _database.rewards,
        )..where((row) => row.id.equals(id) & row.userId.equals(userId))).write(
          RewardsCompanion(imageKey: Value(imageKey), updatedAt: Value(now)),
        );
        final updated = await getById(userId, id);
        await _enqueueReward(updated!, 'update');
        return updated;
      });

  Future<PointLedgerData> redeem({
    required String userId,
    required String rewardId,
    String? redemptionId,
  }) async {
    if (authoritativeRemoteRedemption) {
      return _redeemAuthoritatively(
        userId: userId,
        rewardId: rewardId,
        redemptionId: redemptionId,
      );
    }
    return _database.transaction(() async {
      final sourceId = redemptionId ?? createDatabaseUuid();
      _validateUuid(sourceId);
      final existing = await _getRedemption(userId, sourceId);
      if (existing != null) return existing;

      final reward = await getById(userId, rewardId);
      if (reward == null || reward.archivedAt != null) {
        throw ArgumentError.value(rewardId, 'rewardId');
      }
      final availablePoints = await _availablePoints(userId);
      if (availablePoints < reward.pointsCost) {
        throw InsufficientPointsException(
          availablePoints: availablePoints,
          requiredPoints: reward.pointsCost,
        );
      }

      final redemption = await _database
          .into(_database.pointLedger)
          .insertReturning(
            PointLedgerCompanion.insert(
              userId: userId,
              sourceType: PointLedgerSourceType.rewardRedemption,
              sourceId: sourceId,
              points: -reward.pointsCost,
              reason: Value('Reward: ${reward.name}'),
              rewardId: Value(reward.id),
            ),
          );
      await _sync.enqueue(
        userId: userId,
        entityType: 'point_ledger',
        entityId: redemption.id,
        operation: 'create',
      );
      return redemption;
    });
  }

  Future<PointLedgerData> _redeemAuthoritatively({
    required String userId,
    required String rewardId,
    String? redemptionId,
  }) async {
    final reward = await getById(userId, rewardId);
    if (reward == null || reward.archivedAt != null) {
      throw ArgumentError.value(rewardId, 'rewardId');
    }
    RewardRedemptionRequest? request;
    if (redemptionId != null) {
      _validateUuid(redemptionId);
      request =
          await (_database.select(_database.rewardRedemptionRequests)..where(
                (row) =>
                    row.id.equals(redemptionId) & row.userId.equals(userId),
              ))
              .getSingleOrNull();
    } else {
      final unresolved =
          await (_database.select(_database.rewardRedemptionRequests)
                ..where(
                  (row) =>
                      row.userId.equals(userId) &
                      row.rewardId.equals(rewardId) &
                      row.status.isIn(['pending', 'completed']),
                )
                ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
              .get();
      for (final candidate in unresolved) {
        if (await _getRedemption(userId, candidate.id) == null) {
          request = candidate;
          break;
        }
      }
    }
    final sourceId = request?.id ?? redemptionId ?? createDatabaseUuid();
    final existing = await _getRedemption(userId, sourceId);
    if (existing != null) return existing;

    request ??= await _database.transaction(() async {
      final created = await _database
          .into(_database.rewardRedemptionRequests)
          .insertReturning(
            RewardRedemptionRequestsCompanion.insert(
              id: sourceId,
              userId: userId,
              rewardId: rewardId,
            ),
          );
      await _sync.enqueue(
        userId: userId,
        entityType: 'reward_redemption',
        entityId: created.id,
        operation: 'create',
      );
      return created;
    });

    await _sync.synchronize(userId, retryFailures: true);
    final result = await _getRedemption(userId, sourceId);
    if (result != null) return result;
    final queued =
        await (_database.select(_database.syncQueue)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.entityType.equals('reward_redemption') &
                  row.entityId.equals(sourceId),
            ))
            .getSingleOrNull();
    final detail =
        queued?.lastError ?? 'Redemption is waiting for synchronization.';
    if (queued?.attempts == -1) {
      await (_database.update(_database.rewardRedemptionRequests)..where(
            (row) => row.id.equals(sourceId) & row.userId.equals(userId),
          ))
          .write(
            RewardRedemptionRequestsCompanion(
              status: const Value('rejected'),
              lastError: Value(detail),
              updatedAt: Value(DateTime.now().toUtc()),
            ),
          );
    }
    if (detail.contains('insufficient points')) {
      throw InsufficientPointsException(
        availablePoints: await _availablePoints(userId),
        requiredPoints: reward.pointsCost,
      );
    }
    throw RedemptionPendingException(detail);
  }

  Future<PointLedgerData?> getRedemption(String userId, String redemptionId) {
    return _getRedemption(userId, redemptionId);
  }

  Future<PointLedgerData?> _getRedemption(String userId, String sourceId) {
    final storedType = const PointLedgerSourceTypeConverter().toSql(
      PointLedgerSourceType.rewardRedemption,
    );
    final query = _database.select(_database.pointLedger)
      ..where(
        (row) =>
            row.userId.equals(userId) &
            row.sourceType.equals(storedType) &
            row.sourceId.equals(sourceId),
      );
    return query.getSingleOrNull();
  }

  Future<int> _availablePoints(String userId) async {
    final total = _database.pointLedger.points.sum();
    final query = _database.selectOnly(_database.pointLedger)
      ..addColumns([total])
      ..where(_database.pointLedger.userId.equals(userId));
    return (await query.getSingle()).read(total) ?? 0;
  }

  Future<void> _enqueueReward(Reward reward, String operation) => _sync.enqueue(
    userId: reward.userId,
    entityType: 'reward',
    entityId: reward.id,
    operation: operation,
  );

  String _validName(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) throw ArgumentError.value(name, 'name');
    return normalized;
  }

  void _validate({required int pointsCost, required double? monetaryCap}) {
    if (pointsCost <= 0) {
      throw ArgumentError.value(pointsCost, 'pointsCost', 'Must be positive');
    }
    if (monetaryCap != null && monetaryCap < 0) {
      throw ArgumentError.value(
        monetaryCap,
        'monetaryCap',
        'Must be zero or positive',
      );
    }
  }

  void _validateUuid(String value) {
    final valid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-'
      r'[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
    if (!valid) {
      throw ArgumentError.value(value, 'redemptionId', 'Must be UUID');
    }
  }
}

class InsufficientPointsException implements Exception {
  const InsufficientPointsException({
    required this.availablePoints,
    required this.requiredPoints,
  });

  final int availablePoints;
  final int requiredPoints;

  @override
  String toString() =>
      'Insufficient points: $availablePoints available, $requiredPoints required';
}

class RedemptionPendingException implements Exception {
  const RedemptionPendingException(this.message);
  final String message;

  @override
  String toString() => message;
}
