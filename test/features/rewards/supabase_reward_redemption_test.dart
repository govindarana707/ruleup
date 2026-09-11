import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/database/database_uuid.dart';
import 'package:ruleup/core/sync/sync_service.dart';
import 'package:ruleup/core/sync/sync_transport.dart';
import 'package:ruleup/features/points/data/point_ledger_repository.dart';
import 'package:ruleup/features/points/domain/point_ledger_source_type.dart';
import 'package:ruleup/features/rewards/data/reward_repository.dart';

void main() {
  late AppDatabase database;
  late _RedemptionTransport transport;
  late SyncService sync;
  late RewardRepository rewards;
  late String userId;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    userId =
        (await database
                .into(database.localUsers)
                .insertReturning(LocalUsersCompanion.insert()))
            .id;
    transport = _RedemptionTransport(database, userId);
    sync = SyncService(database, transport);
    rewards = RewardRepository(
      database,
      sync,
      authoritativeRemoteRedemption: true,
    );
  });

  tearDown(() => database.close());

  test(
    'remote-first redemption becomes local only after RPC acceptance',
    () async {
      await _addPoints(database, userId, 80);
      final reward = await rewards.create(
        userId: userId,
        name: 'Dinner',
        pointsCost: 60,
      );
      final redemptionId = createDatabaseUuid();

      final redemption = await rewards.redeem(
        userId: userId,
        rewardId: reward.id,
        redemptionId: redemptionId,
      );
      final wallet = await PointLedgerRepository(
        database,
        sync,
      ).getWallet(userId);

      expect(redemption.sourceId, redemptionId);
      expect(redemption.rewardId, reward.id);
      expect(redemption.points, -60);
      expect(wallet.availablePoints, 20);
      expect(wallet.lifetimeEarned, 80);
      expect(wallet.spentPoints, 60);
      expect(transport.redemptionCalls, 1);
      expect(
        (await database.select(database.rewardRedemptionRequests).getSingle())
            .status,
        'completed',
      );
    },
  );

  test('offline request remains durable without optimistic spending', () async {
    await _addPoints(database, userId, 80);
    final reward = await rewards.create(
      userId: userId,
      name: 'Dinner',
      pointsCost: 60,
    );
    transport.offline = true;

    await expectLater(
      rewards.redeem(userId: userId, rewardId: reward.id),
      throwsA(isA<RedemptionPendingException>()),
    );
    expect(
      (await PointLedgerRepository(database, sync).getWallet(userId))
          .availablePoints,
      80,
    );
    expect(
      await database.select(database.rewardRedemptionRequests).get(),
      hasLength(1),
    );

    transport.offline = false;
    final redemption = await rewards.redeem(
      userId: userId,
      rewardId: reward.id,
    );
    expect(redemption.points, -60);
    expect(transport.redemptionCalls, 1);
    expect(await database.select(database.syncQueue).get(), isEmpty);
  });

  test(
    'insufficient remote balance leaves wallet and ledger unchanged',
    () async {
      await _addPoints(database, userId, 50);
      final reward = await rewards.create(
        userId: userId,
        name: 'Dinner',
        pointsCost: 80,
      );
      transport.insufficient = true;

      await expectLater(
        rewards.redeem(userId: userId, rewardId: reward.id),
        throwsA(isA<InsufficientPointsException>()),
      );
      final wallet = await PointLedgerRepository(
        database,
        sync,
      ).getWallet(userId);
      expect(wallet.availablePoints, 50);
      expect(wallet.spentPoints, 0);
      expect(
        await (database.select(
          database.pointLedger,
        )..where((row) => row.sourceType.equals('reward_redemption'))).get(),
        isEmpty,
      );
    },
  );

  test(
    'completed RPC awaiting pull is reused after restart boundary',
    () async {
      await _addPoints(database, userId, 80);
      final reward = await rewards.create(
        userId: userId,
        name: 'Dinner',
        pointsCost: 60,
      );
      transport.suppressPull = true;

      await expectLater(
        rewards.redeem(userId: userId, rewardId: reward.id),
        throwsA(isA<RedemptionPendingException>()),
      );
      expect(transport.redemptionCalls, 1);

      transport.suppressPull = false;
      final redemption = await rewards.redeem(
        userId: userId,
        rewardId: reward.id,
      );
      expect(redemption.points, -60);
      expect(transport.redemptionCalls, 1);
      expect(
        await database.select(database.rewardRedemptionRequests).get(),
        hasLength(1),
      );
    },
  );
}

Future<void> _addPoints(AppDatabase database, String userId, int points) =>
    database
        .into(database.pointLedger)
        .insert(
          PointLedgerCompanion.insert(
            userId: userId,
            sourceType: PointLedgerSourceType.checkIn,
            sourceId: createDatabaseUuid(),
            points: points,
          ),
        );

class _RedemptionTransport
    implements
        ScopedSyncTransport,
        UserScopedPullSyncTransport,
        CursorScopedPullSyncTransport {
  _RedemptionTransport(this.database, this.userId);
  final AppDatabase database;
  final String userId;
  RemoteChange? change;
  bool offline = false;
  bool insufficient = false;
  bool suppressPull = false;
  int redemptionCalls = 0;

  @override
  String get cursorMetadataKey => 'test_redemption_cursor';

  @override
  bool supports(String entityType) =>
      entityType == 'reward' || entityType == 'reward_redemption';

  @override
  Future<void> send(SyncQueueData item) async {
    if (item.entityType == 'reward') return;
    if (offline) throw const _RetryableFailure('offline');
    if (insufficient) {
      throw const _PermanentFailure('validation: insufficient points');
    }
    redemptionCalls++;
    final request = await (database.select(
      database.rewardRedemptionRequests,
    )..where((row) => row.id.equals(item.entityId))).getSingle();
    final reward = await (database.select(
      database.rewards,
    )..where((row) => row.id.equals(request.rewardId))).getSingle();
    final timestamp = DateTime.utc(2026, 9, 11, 9);
    change = RemoteChange(
      cursor: '1',
      entityType: 'point_ledger',
      operation: 'upsert',
      updatedAt: timestamp,
      data: {
        'id': request.ledgerId,
        'sourceType': 'reward_redemption',
        'sourceId': request.id,
        'points': -reward.pointsCost,
        'reason': 'Reward: ${reward.name}',
        'rewardId': reward.id,
        'createdAt': timestamp.toIso8601String(),
        'updatedAt': timestamp.toIso8601String(),
      },
    );
    await (database.update(
      database.rewardRedemptionRequests,
    )..where((row) => row.id.equals(request.id))).write(
      RewardRedemptionRequestsCompanion(status: const Value('completed')),
    );
  }

  @override
  Future<PullBatch> pull(String cursor) => pullForUser(userId, cursor);

  @override
  Future<PullBatch> pullForUser(String userId, String cursor) async {
    final current = change;
    if (suppressPull || current == null || cursor == '1') {
      return PullBatch(changes: const [], nextCursor: cursor, hasMore: false);
    }
    change = null;
    return PullBatch(changes: [current], nextCursor: '1', hasMore: false);
  }
}

class _RetryableFailure implements ClassifiedSyncFailure {
  const _RetryableFailure(this.message);
  final String message;
  @override
  bool get retryable => true;
  @override
  String toString() => message;
}

class _PermanentFailure implements ClassifiedSyncFailure {
  const _PermanentFailure(this.message);
  final String message;
  @override
  bool get retryable => false;
  @override
  String toString() => message;
}
