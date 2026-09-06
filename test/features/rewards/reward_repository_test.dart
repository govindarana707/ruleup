import 'package:drift/drift.dart' hide isNotNull, isNull;
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
  late RewardRepository rewards;
  late PointLedgerRepository ledger;
  late String userId;
  late String otherUserId;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final sync = SyncService(database, const _UnusedTransport());
    rewards = RewardRepository(database, sync);
    ledger = PointLedgerRepository(database, sync);
    userId = await _createUser(database);
    otherUserId = await _createUser(database);
  });

  tearDown(() => database.close());

  test('reward CRUD validates values and enqueues local writes', () async {
    final created = await rewards.create(
      userId: userId,
      name: '  Movie night  ',
      pointsCost: 25,
      monetaryCap: 12.5,
      sortOrder: 2,
    );

    expect(created.name, 'Movie night');
    expect(created.pointsCost, 25);
    expect(created.monetaryCap, 12.5);
    final updated = await rewards.update(
      userId: userId,
      id: created.id,
      name: 'Book',
      pointsCost: 15,
      monetaryCap: 0,
      sortOrder: 1,
    );
    expect(updated?.name, 'Book');
    expect(updated?.pointsCost, 15);
    expect(updated?.monetaryCap, 0);

    await expectLater(
      rewards.create(userId: userId, name: 'Invalid', pointsCost: 0),
      throwsArgumentError,
    );
    await expectLater(
      rewards.create(
        userId: userId,
        name: 'Invalid',
        pointsCost: 1,
        monetaryCap: -0.01,
      ),
      throwsArgumentError,
    );

    final operations =
        (await (database.select(database.syncQueue)..where(
                  (row) =>
                      row.entityType.equals('reward') &
                      row.entityId.equals(created.id),
                ))
                .get())
            .map((item) => item.operation)
            .toSet();
    expect(operations, {'create', 'update'});
  });

  test('rewards are ordered and archived instead of deleted', () async {
    final second = await rewards.create(
      userId: userId,
      name: 'Second',
      pointsCost: 20,
      sortOrder: 2,
    );
    final first = await rewards.create(
      userId: userId,
      name: 'First',
      pointsCost: 10,
      sortOrder: 1,
    );

    expect((await rewards.list(userId)).map((reward) => reward.id), [
      first.id,
      second.id,
    ]);
    expect(await rewards.archive(userId, first.id), isTrue);
    expect(await rewards.list(userId), [second]);
    expect((await rewards.getById(userId, first.id))?.archivedAt, isNotNull);
    expect(await rewards.list(userId, includeArchived: true), hasLength(2));
    expect(
      await (database.select(database.syncQueue)..where(
            (row) =>
                row.entityType.equals('reward') &
                row.entityId.equals(first.id) &
                row.operation.equals('archive'),
          ))
          .getSingleOrNull(),
      isNotNull,
    );
  });

  test(
    'successful redemption updates derived wallet totals and sync',
    () async {
      await _addPoints(database, userId, 30);
      final reward = await rewards.create(
        userId: userId,
        name: 'Treat',
        pointsCost: 12,
      );
      final redemptionId = createDatabaseUuid();

      final redemption = await rewards.redeem(
        userId: userId,
        rewardId: reward.id,
        redemptionId: redemptionId,
      );
      final wallet = await ledger.getWallet(userId);

      expect(redemption.sourceType, PointLedgerSourceType.rewardRedemption);
      expect(redemption.sourceId, redemptionId);
      expect(redemption.points, -12);
      expect(wallet.availablePoints, 18);
      expect(wallet.lifetimeEarned, 30);
      expect(wallet.spentPoints, 12);
      final queued =
          await (database.select(database.syncQueue)..where(
                (row) =>
                    row.entityType.equals('point_ledger') &
                    row.entityId.equals(redemption.id) &
                    row.operation.equals('create'),
              ))
              .getSingleOrNull();
      expect(queued?.userId, userId);
    },
  );

  test('insufficient points rejects redemption without ledger write', () async {
    await _addPoints(database, userId, 4);
    final reward = await rewards.create(
      userId: userId,
      name: 'Expensive',
      pointsCost: 5,
    );

    await expectLater(
      rewards.redeem(userId: userId, rewardId: reward.id),
      throwsA(isA<InsufficientPointsException>()),
    );

    final redemptions = await (database.select(
      database.pointLedger,
    )..where((row) => row.points.isSmallerThanValue(0))).get();
    expect(redemptions, isEmpty);
  });

  test('same redemption UUID is idempotent and never charges twice', () async {
    await _addPoints(database, userId, 20);
    final reward = await rewards.create(
      userId: userId,
      name: 'Coffee',
      pointsCost: 5,
    );
    final redemptionId = createDatabaseUuid();

    final first = await rewards.redeem(
      userId: userId,
      rewardId: reward.id,
      redemptionId: redemptionId,
    );
    final second = await rewards.redeem(
      userId: userId,
      rewardId: reward.id,
      redemptionId: redemptionId,
    );

    expect(second.id, first.id);
    expect((await ledger.getWallet(userId)).availablePoints, 15);
    final entries = await (database.select(
      database.pointLedger,
    )..where((row) => row.sourceId.equals(redemptionId))).get();
    expect(entries, hasLength(1));
  });

  test('reward access and redemptions remain user isolated', () async {
    await _addPoints(database, userId, 10);
    await _addPoints(database, otherUserId, 10);
    final reward = await rewards.create(
      userId: userId,
      name: 'Private reward',
      pointsCost: 5,
    );

    expect(await rewards.getById(otherUserId, reward.id), isNull);
    expect(
      await rewards.update(
        userId: otherUserId,
        id: reward.id,
        name: 'Changed',
        pointsCost: 1,
        monetaryCap: null,
        sortOrder: 0,
      ),
      isNull,
    );
    expect(await rewards.archive(otherUserId, reward.id), isFalse);
    await expectLater(
      rewards.redeem(userId: otherUserId, rewardId: reward.id),
      throwsArgumentError,
    );
    expect((await ledger.getWallet(userId)).availablePoints, 10);
    expect((await ledger.getWallet(otherUserId)).availablePoints, 10);
  });
}

Future<String> _createUser(AppDatabase database) async =>
    (await database
            .into(database.localUsers)
            .insertReturning(LocalUsersCompanion.insert()))
        .id;

Future<void> _addPoints(AppDatabase database, String userId, int points) async {
  await database
      .into(database.pointLedger)
      .insert(
        PointLedgerCompanion.insert(
          userId: userId,
          sourceType: PointLedgerSourceType.checkIn,
          sourceId: createDatabaseUuid(),
          points: points,
          reason: const Value('Test award'),
        ),
      );
}

class _UnusedTransport implements SyncTransport {
  const _UnusedTransport();

  @override
  Future<void> send(SyncQueueData item) => throw UnimplementedError();
}
