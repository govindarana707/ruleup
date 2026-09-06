import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/sync/sync_service.dart';
import 'package:ruleup/core/sync/sync_transport.dart';
import 'package:ruleup/features/check_ins/data/check_in_repository.dart';
import 'package:ruleup/features/habits/data/habit_pause_repository.dart';
import 'package:ruleup/features/habits/domain/measurement_type.dart';
import 'package:ruleup/features/points/domain/point_rule_operator.dart';

void main() {
  late AppDatabase database;
  late SyncService sync;
  late HabitPauseRepository pauses;
  late String userId;
  late String otherUserId;
  late String habitId;
  late String otherHabitId;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    sync = SyncService(database, const _UnusedTransport());
    pauses = HabitPauseRepository(database, sync);
    userId = await _createUser(database);
    otherUserId = await _createUser(database);
    habitId = await _createHabit(database, userId);
    otherHabitId = await _createHabit(database, otherUserId);
  });

  tearDown(() => database.close());

  test('pause CRUD normalizes dates and enqueues sync', () async {
    final created = await pauses.create(
      userId: userId,
      habitId: habitId,
      startDate: DateTime(2026, 1, 5, 20),
      endDate: DateTime(2026, 1, 7, 8),
    );
    expect(created.startDate, DateTime.utc(2026, 1, 5));
    expect(created.endDate, DateTime.utc(2026, 1, 7));

    final updated = await pauses.update(
      userId: userId,
      id: created.id,
      habitId: habitId,
      startDate: DateTime(2026, 1, 6),
      endDate: DateTime(2026, 1, 8),
    );
    expect(updated?.startDate, DateTime.utc(2026, 1, 6));
    expect(await pauses.getById(userId, created.id), isNotNull);

    expect(await pauses.delete(userId, created.id), isTrue);
    expect(await pauses.getById(userId, created.id), isNull);

    final queue = await database.select(database.syncQueue).get();
    expect(queue.map((item) => item.entityType).toSet(), {'habit_pause'});
    expect(queue.map((item) => item.operation).toSet(), {
      'create',
      'update',
      'delete',
    });
  });

  test('pauses are ordered and reject invalid or overlapping ranges', () async {
    final later = await pauses.create(
      userId: userId,
      habitId: habitId,
      startDate: DateTime(2026, 2, 10),
      endDate: DateTime(2026, 2, 12),
    );
    final earlier = await pauses.create(
      userId: userId,
      habitId: habitId,
      startDate: DateTime(2026, 2, 1),
      endDate: DateTime(2026, 2, 3),
    );
    expect(
      (await pauses.listForHabit(userId, habitId)).map((item) => item.id),
      [earlier.id, later.id],
    );

    await expectLater(
      pauses.create(
        userId: userId,
        habitId: habitId,
        startDate: DateTime(2026, 2, 4),
        endDate: DateTime(2026, 2, 2),
      ),
      throwsArgumentError,
    );
    await expectLater(
      pauses.create(
        userId: userId,
        habitId: habitId,
        startDate: DateTime(2026, 2, 3),
        endDate: DateTime(2026, 2, 5),
      ),
      throwsA(isA<OverlappingHabitPauseException>()),
    );
  });

  test(
    'pause repository isolates users and enforces habit ownership',
    () async {
      final pause = await pauses.create(
        userId: userId,
        habitId: habitId,
        startDate: DateTime(2026, 3, 1),
        endDate: DateTime(2026, 3, 2),
      );

      expect(await pauses.getById(otherUserId, pause.id), isNull);
      expect(await pauses.listForHabit(otherUserId, habitId), isEmpty);
      expect(await pauses.delete(otherUserId, pause.id), isFalse);
      await expectLater(
        pauses.create(
          userId: userId,
          habitId: otherHabitId,
          startDate: DateTime(2026, 3, 3),
          endDate: DateTime(2026, 3, 4),
        ),
        throwsArgumentError,
      );
    },
  );

  test('a check-in on a paused day receives no points', () async {
    await database
        .into(database.pointRules)
        .insert(
          PointRulesCompanion.insert(
            userId: userId,
            habitId: habitId,
            operator: PointRuleOperator.completed,
            points: 10,
          ),
        );
    await pauses.create(
      userId: userId,
      habitId: habitId,
      startDate: DateTime(2026, 4, 1),
      endDate: DateTime(2026, 4, 2),
    );
    final checkIns = CheckInRepository(
      database,
      sync,
      now: () => DateTime.utc(2026, 4, 1, 12),
    );

    final checkIn = await checkIns.create(
      userId: userId,
      habitId: habitId,
      habitDate: DateTime(2026, 4, 1),
    );
    final award = await database.select(database.pointLedger).getSingle();

    expect(checkIn.awardedPoints, 0);
    expect(checkIn.matchedRuleId, isNull);
    expect(award.points, 0);
  });
}

Future<String> _createUser(AppDatabase database) async =>
    (await database
            .into(database.localUsers)
            .insertReturning(LocalUsersCompanion.insert()))
        .id;

Future<String> _createHabit(AppDatabase database, String userId) async =>
    (await database
            .into(database.habits)
            .insertReturning(
              HabitsCompanion.insert(
                userId: userId,
                name: 'Habit',
                measurementType: MeasurementType.yesNo,
              ),
            ))
        .id;

class _UnusedTransport implements SyncTransport {
  const _UnusedTransport();

  @override
  Future<void> send(SyncQueueData item) => throw UnimplementedError();
}
