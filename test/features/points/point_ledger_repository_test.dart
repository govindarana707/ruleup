import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/sync/sync_service.dart';
import 'package:ruleup/core/sync/sync_transport.dart';
import 'package:ruleup/features/check_ins/data/check_in_repository.dart';
import 'package:ruleup/features/habits/domain/measurement_type.dart';
import 'package:ruleup/features/points/data/point_ledger_repository.dart';
import 'package:ruleup/features/points/domain/point_ledger_source_type.dart';
import 'package:ruleup/features/points/domain/point_rule_operator.dart';

void main() {
  late AppDatabase database;
  late PointLedgerRepository ledger;
  late CheckInRepository checkIns;
  late String userId;
  late String otherUserId;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final sync = SyncService(database, const _UnusedTransport());
    ledger = PointLedgerRepository(database, sync);
    checkIns = CheckInRepository(
      database,
      sync,
      pointLedger: ledger,
      now: () => DateTime.utc(2026, 1, 1, 12),
    );
    userId = await _createUser(database);
    otherUserId = await _createUser(database);
  });

  tearDown(() => database.close());

  test('check-in creation creates one matching ledger award', () async {
    final habitId = await _createHabit(database, userId, MeasurementType.yesNo);
    await _createRule(
      database,
      userId: userId,
      habitId: habitId,
      operator: PointRuleOperator.completed,
      points: 6,
    );

    final checkIn = await checkIns.create(
      userId: userId,
      habitId: habitId,
      habitDate: DateTime(2026, 1, 1),
    );
    final award = await ledger.getForCheckIn(userId, checkIn.id);

    expect(award?.sourceType, PointLedgerSourceType.checkIn);
    expect(award?.sourceId, checkIn.id);
    expect(award?.points, 6);
    expect(award?.reason, isNull);
    expect(await database.select(database.pointLedger).get(), hasLength(1));

    final queued = await database.select(database.syncQueue).get();
    expect(
      queued.any(
        (item) =>
            item.entityType == 'point_ledger' && item.operation == 'create',
      ),
      isTrue,
    );
  });

  test('reconciliation does not create duplicate awards', () async {
    final habitId = await _createHabit(database, userId, MeasurementType.yesNo);
    final checkIn = await checkIns.create(
      userId: userId,
      habitId: habitId,
      habitDate: DateTime(2026, 1, 1),
    );
    final original = await ledger.getForCheckIn(userId, checkIn.id);

    final first = await ledger.reconcileCheckIn(
      userId: userId,
      checkInId: checkIn.id,
    );
    final second = await ledger.reconcileCheckIn(
      userId: userId,
      checkInId: checkIn.id,
    );

    expect(first.id, original?.id);
    expect(second.id, original?.id);
    expect(await database.select(database.pointLedger).get(), hasLength(1));
  });

  test('editable check-in reconciles the existing ledger snapshot', () async {
    final habitId = await _createHabit(
      database,
      userId,
      MeasurementType.duration,
    );
    await _createRule(
      database,
      userId: userId,
      habitId: habitId,
      operator: PointRuleOperator.gte,
      valueMin: 30,
      points: 5,
    );
    await _createRule(
      database,
      userId: userId,
      habitId: habitId,
      operator: PointRuleOperator.gte,
      valueMin: 60,
      points: 10,
    );
    final checkIn = await checkIns.create(
      userId: userId,
      habitId: habitId,
      habitDate: DateTime(2026, 1, 1),
      measuredValue: 40,
    );
    final original = await ledger.getForCheckIn(userId, checkIn.id);
    expect(original?.points, 5);

    await checkIns.update(
      userId: userId,
      id: checkIn.id,
      optionId: null,
      measuredValue: 70,
      note: null,
    );
    final reconciled = await ledger.getForCheckIn(userId, checkIn.id);

    expect(reconciled?.id, original?.id);
    expect(reconciled?.points, 10);
    expect(await database.select(database.pointLedger).get(), hasLength(1));

    final queued = await database.select(database.syncQueue).get();
    expect(
      queued
          .where((item) => item.entityType == 'point_ledger')
          .map((item) => item.operation)
          .toSet(),
      {'create', 'update'},
    );
  });

  test(
    'wallet derives totals and does not treat penalties as spending',
    () async {
      final earningHabit = await _createHabit(
        database,
        userId,
        MeasurementType.yesNo,
      );
      final penaltyHabit = await _createHabit(
        database,
        userId,
        MeasurementType.yesNo,
      );
      await _createRule(
        database,
        userId: userId,
        habitId: earningHabit,
        operator: PointRuleOperator.completed,
        points: 10,
      );
      await _createRule(
        database,
        userId: userId,
        habitId: penaltyHabit,
        operator: PointRuleOperator.completed,
        points: -3,
      );
      await checkIns.create(
        userId: userId,
        habitId: earningHabit,
        habitDate: DateTime(2026, 1, 1),
      );
      await checkIns.create(
        userId: userId,
        habitId: penaltyHabit,
        habitDate: DateTime(2026, 1, 1),
      );

      final wallet = await ledger.getWallet(userId);
      expect(wallet.availablePoints, 7);
      expect(wallet.lifetimeEarned, 10);
      expect(wallet.spentPoints, 0);
    },
  );

  test(
    'ledger reads, reconciliation, and wallet totals isolate users',
    () async {
      final habitId = await _createHabit(
        database,
        userId,
        MeasurementType.yesNo,
      );
      await _createRule(
        database,
        userId: userId,
        habitId: habitId,
        operator: PointRuleOperator.completed,
        points: 4,
      );
      final checkIn = await checkIns.create(
        userId: userId,
        habitId: habitId,
        habitDate: DateTime(2026, 1, 1),
      );

      expect(await ledger.getForCheckIn(otherUserId, checkIn.id), isNull);
      final otherWallet = await ledger.getWallet(otherUserId);
      expect(otherWallet.availablePoints, 0);
      expect(otherWallet.lifetimeEarned, 0);
      expect(otherWallet.spentPoints, 0);
      await expectLater(
        ledger.reconcileCheckIn(userId: otherUserId, checkInId: checkIn.id),
        throwsArgumentError,
      );
    },
  );
}

Future<String> _createUser(AppDatabase database) async =>
    (await database
            .into(database.localUsers)
            .insertReturning(LocalUsersCompanion.insert()))
        .id;

Future<String> _createHabit(
  AppDatabase database,
  String userId,
  MeasurementType measurementType,
) async =>
    (await database
            .into(database.habits)
            .insertReturning(
              HabitsCompanion.insert(
                userId: userId,
                name: 'Habit',
                measurementType: measurementType,
              ),
            ))
        .id;

Future<void> _createRule(
  AppDatabase database, {
  required String userId,
  required String habitId,
  required PointRuleOperator operator,
  required int points,
  double? valueMin,
}) async {
  await database
      .into(database.pointRules)
      .insert(
        PointRulesCompanion.insert(
          userId: userId,
          habitId: habitId,
          operator: operator,
          valueMin: Value(valueMin),
          points: points,
        ),
      );
}

class _UnusedTransport implements SyncTransport {
  const _UnusedTransport();

  @override
  Future<void> send(SyncQueueData item) => throw UnimplementedError();
}
