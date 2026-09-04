import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/sync/sync_service.dart';
import 'package:ruleup/core/sync/sync_transport.dart';
import 'package:ruleup/features/check_ins/data/check_in_repository.dart';
import 'package:ruleup/features/habits/domain/measurement_type.dart';
import 'package:ruleup/features/points/domain/point_rule_operator.dart';

void main() {
  late AppDatabase database;
  late CheckInRepository checkIns;
  late DateTime currentTime;
  late String userId;
  late String otherUserId;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    currentTime = DateTime.utc(2026, 1, 1, 12);
    checkIns = CheckInRepository(
      database,
      SyncService(database, const _UnusedTransport()),
      now: () => currentTime,
    );
    userId = await _createUser(database);
    otherUserId = await _createUser(database);
  });

  tearDown(() => database.close());

  test('creates a daily check-in with a point snapshot', () async {
    final habitId = await _createHabit(database, userId, MeasurementType.yesNo);
    final ownRuleId = await _createRule(
      database,
      userId: userId,
      habitId: habitId,
      operator: PointRuleOperator.completed,
      points: 7,
    );
    await _createRule(
      database,
      userId: otherUserId,
      habitId: habitId,
      operator: PointRuleOperator.completed,
      points: 100,
    );

    final checkIn = await checkIns.create(
      userId: userId,
      habitId: habitId,
      habitDate: DateTime(2026, 1, 1, 20),
      note: '  Done before dinner  ',
    );

    expect(checkIn.habitDate, DateTime.utc(2026, 1, 1));
    expect(checkIn.checkedInAt.toUtc(), currentTime);
    expect(checkIn.editableUntil.toUtc(), DateTime.utc(2026, 1, 2, 12));
    expect(checkIn.note, 'Done before dinner');
    expect(checkIn.awardedPoints, 7);
    expect(checkIn.matchedRuleId, ownRuleId);
  });

  test('valid edit recalculates points without stacking', () async {
    final habitId = await _createHabit(
      database,
      userId,
      MeasurementType.duration,
    );
    final baseRuleId = await _createRule(
      database,
      userId: userId,
      habitId: habitId,
      operator: PointRuleOperator.gte,
      valueMin: 30,
      points: 5,
    );
    final highRuleId = await _createRule(
      database,
      userId: userId,
      habitId: habitId,
      operator: PointRuleOperator.gte,
      valueMin: 60,
      points: 10,
    );
    final created = await checkIns.create(
      userId: userId,
      habitId: habitId,
      habitDate: DateTime(2026, 1, 1),
      measuredValue: 40,
    );
    expect(created.awardedPoints, 5);
    expect(created.matchedRuleId, baseRuleId);

    currentTime = DateTime.utc(2026, 1, 2, 11);
    final updated = await checkIns.update(
      userId: userId,
      id: created.id,
      optionId: null,
      measuredValue: 70,
      note: 'Long session',
    );

    expect(updated?.awardedPoints, 10);
    expect(updated?.matchedRuleId, highRuleId);
    expect(updated?.measuredValue, 70);
    expect(await checkIns.listForDate(userId, created.habitDate), hasLength(1));

    final queue = await database.select(database.syncQueue).get();
    expect(queue.map((item) => item.entityType).toSet(), {
      'check_in',
      'point_ledger',
    });
    expect(queue.map((item) => item.operation).toSet(), {'create', 'update'});
  });

  test('owned option numeric value is used for evaluation', () async {
    final habitId = await _createHabit(database, userId, MeasurementType.count);
    final optionId = await _createOption(
      database,
      userId: userId,
      habitId: habitId,
      numericValue: 10,
    );
    final ruleId = await _createRule(
      database,
      userId: userId,
      habitId: habitId,
      operator: PointRuleOperator.gte,
      valueMin: 10,
      points: 4,
    );

    final checkIn = await checkIns.create(
      userId: userId,
      habitId: habitId,
      habitDate: DateTime(2026, 1, 1),
      optionId: optionId,
    );

    expect(checkIn.optionId, optionId);
    expect(checkIn.measuredValue, isNull);
    expect(checkIn.awardedPoints, 4);
    expect(checkIn.matchedRuleId, ruleId);
  });

  test('edit is locked after the habit day plus twelve hours', () async {
    final habitId = await _createHabit(database, userId, MeasurementType.yesNo);
    final created = await checkIns.create(
      userId: userId,
      habitId: habitId,
      habitDate: DateTime(2026, 1, 1),
      note: 'Original',
    );

    currentTime = DateTime.utc(2026, 1, 2, 12, 0, 1);
    await expectLater(
      checkIns.update(
        userId: userId,
        id: created.id,
        optionId: null,
        measuredValue: null,
        note: 'Too late',
      ),
      throwsA(isA<CheckInLockedException>()),
    );
    expect((await checkIns.getById(userId, created.id))?.note, 'Original');
  });

  test('rejects a duplicate check-in for the same habit day', () async {
    final habitId = await _createHabit(database, userId, MeasurementType.yesNo);
    await checkIns.create(
      userId: userId,
      habitId: habitId,
      habitDate: DateTime(2026, 1, 1, 8),
    );

    await expectLater(
      checkIns.create(
        userId: userId,
        habitId: habitId,
        habitDate: DateTime(2026, 1, 1, 22),
      ),
      throwsA(isA<DuplicateCheckInException>()),
    );
    expect(
      await checkIns.listForDate(userId, DateTime(2026, 1, 1)),
      hasLength(1),
    );
  });

  test('isolates users and enforces habit and option ownership', () async {
    final habitId = await _createHabit(database, userId, MeasurementType.count);
    final otherHabitId = await _createHabit(
      database,
      otherUserId,
      MeasurementType.count,
    );
    final otherOptionId = await _createOption(
      database,
      userId: otherUserId,
      habitId: otherHabitId,
      numericValue: 1,
    );
    final created = await checkIns.create(
      userId: userId,
      habitId: habitId,
      habitDate: DateTime(2026, 1, 1),
      measuredValue: 1,
    );

    expect(await checkIns.getById(otherUserId, created.id), isNull);
    expect(await checkIns.listForDate(otherUserId, created.habitDate), isEmpty);
    expect(
      await checkIns.update(
        userId: otherUserId,
        id: created.id,
        optionId: null,
        measuredValue: 2,
        note: null,
      ),
      isNull,
    );
    await expectLater(
      checkIns.create(
        userId: userId,
        habitId: otherHabitId,
        habitDate: DateTime(2026, 1, 2),
      ),
      throwsArgumentError,
    );
    await expectLater(
      checkIns.update(
        userId: userId,
        id: created.id,
        optionId: otherOptionId,
        measuredValue: null,
        note: null,
      ),
      throwsArgumentError,
    );
  });
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

Future<String> _createOption(
  AppDatabase database, {
  required String userId,
  required String habitId,
  required double numericValue,
}) async =>
    (await database
            .into(database.habitOptions)
            .insertReturning(
              HabitOptionsCompanion.insert(
                userId: userId,
                habitId: habitId,
                label: 'Option',
                numericValue: Value(numericValue),
              ),
            ))
        .id;

Future<String> _createRule(
  AppDatabase database, {
  required String userId,
  required String habitId,
  required PointRuleOperator operator,
  required int points,
  double? valueMin,
  double? valueMax,
}) async =>
    (await database
            .into(database.pointRules)
            .insertReturning(
              PointRulesCompanion.insert(
                userId: userId,
                habitId: habitId,
                operator: operator,
                valueMin: Value(valueMin),
                valueMax: Value(valueMax),
                points: points,
              ),
            ))
        .id;

class _UnusedTransport implements SyncTransport {
  const _UnusedTransport();

  @override
  Future<void> send(SyncQueueData item) => throw UnimplementedError();
}
