import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/database/tables/point_ledger.dart';
import 'package:ruleup/core/sync/sync_retention_pruner.dart';

void main() {
  late AppDatabase database;
  const userId = '10000000-0000-4000-8000-000000000001';
  const otherUserId = '10000000-0000-4000-8000-000000000002';
  const rewardId = '20000000-0000-4000-8000-000000000001';
  const otherRewardId = '20000000-0000-4000-8000-000000000002';
  final old = DateTime.utc(2026, 1, 1);
  final recent = DateTime.utc(2026, 9, 1);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    for (final id in [userId, otherUserId]) {
      await database
          .into(database.localUsers)
          .insert(LocalUsersCompanion.insert(id: Value(id)));
    }
    await database
        .into(database.rewards)
        .insert(
          RewardsCompanion.insert(
            id: const Value(rewardId),
            userId: userId,
            name: 'Own reward',
            pointsCost: 20,
          ),
        );
    await database
        .into(database.rewards)
        .insert(
          RewardsCompanion.insert(
            id: const Value(otherRewardId),
            userId: otherUserId,
            name: 'Other reward',
            pointsCost: 20,
          ),
        );
  });

  tearDown(() => database.close());

  test('prunes only old completed and fully converged work', () async {
    await _imageOperation(database, 'image-prune', userId, rewardId, old, true);
    await _imageOperation(
      database,
      'image-recent',
      userId,
      rewardId,
      recent,
      true,
    );
    await _imageOperation(
      database,
      'image-pending',
      userId,
      rewardId,
      old,
      false,
    );
    await _imageOperation(
      database,
      'image-queued',
      userId,
      rewardId,
      old,
      true,
    );
    await _imageOperation(
      database,
      'image-other-owner',
      otherUserId,
      otherRewardId,
      old,
      true,
    );
    await _queue(database, userId, 'reward_image_delete', 'image-queued');

    await _redemptionRequest(
      database,
      '30000000-0000-4000-8000-000000000001',
      '40000000-0000-4000-8000-000000000001',
      userId,
      rewardId,
      old,
      'completed',
      withLedger: true,
    );
    await _redemptionRequest(
      database,
      '30000000-0000-4000-8000-000000000002',
      '40000000-0000-4000-8000-000000000002',
      userId,
      rewardId,
      old,
      'completed',
    );
    await _redemptionRequest(
      database,
      '30000000-0000-4000-8000-000000000003',
      '40000000-0000-4000-8000-000000000003',
      userId,
      rewardId,
      old,
      'pending',
    );
    await _redemptionRequest(
      database,
      '30000000-0000-4000-8000-000000000004',
      '40000000-0000-4000-8000-000000000004',
      userId,
      rewardId,
      old,
      'completed',
      withLedger: true,
    );
    await _queue(
      database,
      userId,
      'reward_redemption',
      '30000000-0000-4000-8000-000000000004',
    );

    final result = await SyncRetentionPruner(
      database,
      now: () => DateTime.utc(2026, 9, 11),
    ).prune(userId);

    expect(result.rewardImageOperations, 1);
    expect(result.rewardRedemptionRequests, 1);
    expect(
      (await database.select(database.rewardImageOperations).get()).map(
        (row) => row.id,
      ),
      containsAll([
        'image-recent',
        'image-pending',
        'image-queued',
        'image-other-owner',
      ]),
    );
    expect(
      (await database.select(database.rewardRedemptionRequests).get()).map(
        (row) => row.id,
      ),
      containsAll([
        '30000000-0000-4000-8000-000000000002',
        '30000000-0000-4000-8000-000000000003',
        '30000000-0000-4000-8000-000000000004',
      ]),
    );
  });
}

Future<void> _imageOperation(
  AppDatabase database,
  String id,
  String userId,
  String rewardId,
  DateTime updatedAt,
  bool completed,
) => database
    .into(database.rewardImageOperations)
    .insert(
      RewardImageOperationsCompanion.insert(
        id: Value(id),
        userId: userId,
        rewardId: rewardId,
        operation: 'delete',
        objectKey: '$userId/$rewardId/object.jpg',
        completed: Value(completed),
        updatedAt: Value(updatedAt),
      ),
    );

Future<void> _redemptionRequest(
  AppDatabase database,
  String id,
  String ledgerId,
  String userId,
  String rewardId,
  DateTime updatedAt,
  String status, {
  bool withLedger = false,
}) async {
  await database
      .into(database.rewardRedemptionRequests)
      .insert(
        RewardRedemptionRequestsCompanion.insert(
          id: id,
          ledgerId: Value(ledgerId),
          userId: userId,
          rewardId: rewardId,
          status: Value(status),
          updatedAt: Value(updatedAt),
        ),
      );
  if (withLedger) {
    await database
        .into(database.pointLedger)
        .insert(
          PointLedgerCompanion.insert(
            id: Value(ledgerId),
            userId: userId,
            sourceType: PointLedgerSourceType.rewardRedemption,
            sourceId: id,
            points: -20,
            rewardId: Value(rewardId),
          ),
        );
  }
}

Future<void> _queue(
  AppDatabase database,
  String userId,
  String entityType,
  String entityId,
) => database
    .into(database.syncQueue)
    .insert(
      SyncQueueCompanion.insert(
        userId: userId,
        entityType: entityType,
        entityId: entityId,
        operation: 'delete',
      ),
    );
