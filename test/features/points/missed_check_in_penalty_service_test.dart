import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/sync/sync_service.dart';
import 'package:ruleup/core/sync/sync_transport.dart';
import 'package:ruleup/features/habits/data/habit_repository.dart';
import 'package:ruleup/features/habits/domain/measurement_type.dart';
import 'package:ruleup/features/habits/domain/schedule_type.dart';
import 'package:ruleup/features/points/data/missed_check_in_penalty_service.dart';
import 'package:ruleup/features/points/data/point_ledger_repository.dart';
import 'package:ruleup/features/points/domain/point_ledger_source_type.dart';

void main() {
  late AppDatabase database;
  late SyncService sync;
  late PointLedgerRepository ledger;
  late MissedCheckInPenaltyService penalties;
  late HabitRepository habits;
  late String userId;
  late String otherUserId;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    sync = SyncService(database, const _UnusedTransport());
    ledger = PointLedgerRepository(database, sync);
    penalties = MissedCheckInPenaltyService(database, ledger);
    habits = HabitRepository(database, sync);
    userId = await _createUser(database);
    otherUserId = await _createUser(database);
  });

  tearDown(() => database.close());

  test('disabled habit creates no missed penalties', () async {
    final habitId = await _createHabit(
      database,
      userId: userId,
      enabled: false,
      points: -2,
    );

    final created = await penalties.generateForHabit(
      userId: userId,
      habitId: habitId,
      startDate: DateTime(2026, 1, 1),
      currentHabitDate: DateTime(2026, 1, 3),
    );

    expect(created, 0);
    expect(await database.select(database.pointLedger).get(), isEmpty);
  });

  test('penalizes a past applicable miss but never the current day', () async {
    final habitId = await _createHabit(
      database,
      userId: userId,
      enabled: true,
      points: -2,
    );
    await _createCheckIn(database, userId, habitId, DateTime(2026, 1, 1));

    final created = await penalties.generateForHabit(
      userId: userId,
      habitId: habitId,
      startDate: DateTime(2026, 1, 1),
      currentHabitDate: DateTime(2026, 1, 3),
    );
    final entries = await database.select(database.pointLedger).get();

    expect(created, 1);
    expect(entries, hasLength(1));
    expect(entries.single.sourceType, PointLedgerSourceType.missedCheckIn);
    expect(
      entries.single.sourceId,
      PointLedgerRepository.missedCheckInSourceId(
        habitId,
        DateTime(2026, 1, 2),
      ),
    );
    expect(entries.single.points, -2);
    expect(
      await ledger.getForMissedCheckIn(userId, habitId, DateTime(2026, 1, 3)),
      isNull,
    );

    final wallet = await ledger.getWallet(userId);
    expect(wallet.availablePoints, -2);
    expect(wallet.lifetimeEarned, 0);
    expect(wallet.spentPoints, 0);
  });

  test('does not penalize non-applicable scheduled days', () async {
    final habitId = await _createHabit(
      database,
      userId: userId,
      enabled: true,
      points: -3,
    );
    await database
        .into(database.habitSchedules)
        .insert(
          HabitSchedulesCompanion.insert(
            userId: userId,
            habitId: habitId,
            scheduleType: ScheduleType.specificDays,
            scheduleConfig: '{"days":[1]}',
          ),
        );

    final created = await penalties.generateForHabit(
      userId: userId,
      habitId: habitId,
      startDate: DateTime(2026, 1, 5),
      currentHabitDate: DateTime(2026, 1, 8),
    );

    expect(created, 1);
    expect(await database.select(database.pointLedger).get(), hasLength(1));
    expect(
      await ledger.getForMissedCheckIn(userId, habitId, DateTime(2026, 1, 6)),
      isNull,
    );
  });

  test('does not penalize paused days', () async {
    final habitId = await _createHabit(
      database,
      userId: userId,
      enabled: true,
      points: -4,
    );
    await _createCheckIn(database, userId, habitId, DateTime(2026, 2, 1));
    await database
        .into(database.habitPauses)
        .insert(
          HabitPausesCompanion.insert(
            userId: userId,
            habitId: habitId,
            startDate: DateTime(2026, 2, 2),
            endDate: DateTime(2026, 2, 2),
          ),
        );

    final created = await penalties.generateForHabit(
      userId: userId,
      habitId: habitId,
      startDate: DateTime(2026, 2, 1),
      currentHabitDate: DateTime(2026, 2, 4),
    );

    expect(created, 1);
    expect(
      await ledger.getForMissedCheckIn(userId, habitId, DateTime(2026, 2, 2)),
      isNull,
    );
    expect(
      (await ledger.getForMissedCheckIn(
        userId,
        habitId,
        DateTime(2026, 2, 3),
      ))?.points,
      -4,
    );
  });

  test('generation is idempotent and never duplicates sync awards', () async {
    final habitId = await _createHabit(
      database,
      userId: userId,
      enabled: true,
      points: -1,
    );

    final first = await penalties.generateForHabit(
      userId: userId,
      habitId: habitId,
      startDate: DateTime(2026, 3, 1),
      currentHabitDate: DateTime(2026, 3, 3),
    );
    final second = await penalties.generateForHabit(
      userId: userId,
      habitId: habitId,
      startDate: DateTime(2026, 3, 1),
      currentHabitDate: DateTime(2026, 3, 3),
    );

    expect(first, 2);
    expect(second, 0);
    expect(await database.select(database.pointLedger).get(), hasLength(2));
    final queued = await (database.select(
      database.syncQueue,
    )..where((row) => row.entityType.equals('point_ledger'))).get();
    expect(queued, hasLength(2));
    expect(queued.every((item) => item.operation == 'create'), isTrue);
  });

  test(
    'existing penalties remain snapshots after habit settings change',
    () async {
      final habitId = await _createHabit(
        database,
        userId: userId,
        enabled: true,
        points: -2,
      );
      await penalties.generateForHabit(
        userId: userId,
        habitId: habitId,
        startDate: DateTime(2026, 4, 1),
        currentHabitDate: DateTime(2026, 4, 2),
      );
      final habit = await habits.getById(userId, habitId);
      await habits.update(
        userId: userId,
        id: habitId,
        name: habit!.name,
        measurementType: habit.measurementType,
        categoryId: habit.categoryId,
        sortOrder: habit.sortOrder,
        missedPenaltyEnabled: true,
        missedPenaltyPoints: -5,
      );

      final created = await penalties.generateForHabit(
        userId: userId,
        habitId: habitId,
        startDate: DateTime(2026, 4, 1),
        currentHabitDate: DateTime(2026, 4, 3),
      );

      expect(created, 1);
      expect(
        (await ledger.getForMissedCheckIn(
          userId,
          habitId,
          DateTime(2026, 4, 1),
        ))?.points,
        -2,
      );
      expect(
        (await ledger.getForMissedCheckIn(
          userId,
          habitId,
          DateTime(2026, 4, 2),
        ))?.points,
        -5,
      );
    },
  );

  test('penalty settings and generation enforce user isolation', () async {
    await expectLater(
      habits.create(
        userId: userId,
        name: 'Invalid penalty',
        measurementType: MeasurementType.yesNo,
        missedPenaltyEnabled: true,
        missedPenaltyPoints: 1,
      ),
      throwsArgumentError,
    );
    final habitId = await _createHabit(
      database,
      userId: userId,
      enabled: true,
      points: -2,
    );

    await expectLater(
      penalties.generateForHabit(
        userId: otherUserId,
        habitId: habitId,
        startDate: DateTime(2026, 5, 1),
        currentHabitDate: DateTime(2026, 5, 2),
      ),
      throwsArgumentError,
    );
    expect(await database.select(database.pointLedger).get(), isEmpty);
    expect((await ledger.getWallet(otherUserId)).availablePoints, 0);
  });
}

Future<String> _createUser(AppDatabase database) async =>
    (await database
            .into(database.localUsers)
            .insertReturning(LocalUsersCompanion.insert()))
        .id;

Future<String> _createHabit(
  AppDatabase database, {
  required String userId,
  required bool enabled,
  required int points,
}) async =>
    (await database
            .into(database.habits)
            .insertReturning(
              HabitsCompanion.insert(
                userId: userId,
                name: 'Habit',
                measurementType: MeasurementType.yesNo,
                missedPenaltyEnabled: Value(enabled),
                missedPenaltyPoints: Value(points),
              ),
            ))
        .id;

Future<void> _createCheckIn(
  AppDatabase database,
  String userId,
  String habitId,
  DateTime habitDate,
) async {
  await database
      .into(database.checkIns)
      .insert(
        CheckInsCompanion.insert(
          userId: userId,
          habitId: habitId,
          habitDate: habitDate,
          awardedPoints: 0,
          checkedInAt: habitDate,
          editableUntil: habitDate.add(const Duration(hours: 36)),
        ),
      );
}

class _UnusedTransport implements SyncTransport {
  const _UnusedTransport();

  @override
  Future<void> send(SyncQueueData item) => throw UnimplementedError();
}
