import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/database/tables/habits.dart';
import 'package:ruleup/core/database/tables/point_rules.dart';
import 'package:ruleup/core/sync/sync_service.dart';
import 'package:ruleup/core/sync/sync_transport.dart';
import 'package:ruleup/features/points/data/point_rule_repository.dart';

void main() {
  late AppDatabase database;
  late PointRuleRepository rules;
  late String userId;
  late String otherUserId;
  late String habitId;
  late String otherHabitId;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    rules = PointRuleRepository(
      database,
      SyncService(database, const _UnusedTransport()),
    );
    userId = await _createUser(database);
    otherUserId = await _createUser(database);
    habitId = await _createHabit(database, userId, 'Primary');
    otherHabitId = await _createHabit(database, otherUserId, 'Other');
  });

  tearDown(() => database.close());

  test('point rule CRUD allows positive and negative points', () async {
    final created = await rules.create(
      userId: userId,
      habitId: habitId,
      operator: PointRuleOperator.gte,
      valueMin: 10,
      points: 5,
      sortOrder: 2,
    );
    expect(created.points, 5);
    expect(created.valueMin, 10);

    final updated = await rules.update(
      userId: userId,
      id: created.id,
      habitId: habitId,
      operator: PointRuleOperator.between,
      valueMin: 1,
      valueMax: 3,
      points: -2,
      sortOrder: 1,
    );
    expect(updated?.operator, PointRuleOperator.between);
    expect(updated?.valueMax, 3);
    expect(updated?.points, -2);
    expect((await rules.getById(userId, created.id))?.sortOrder, 1);

    final queue = await database.select(database.syncQueue).get();
    expect(queue.map((item) => item.entityType).toSet(), {'point_rule'});
    expect(queue.map((item) => item.operation).toSet(), {'create', 'update'});
  });

  test('point rules are ordered and archived instead of deleted', () async {
    final later = await rules.create(
      userId: userId,
      habitId: habitId,
      operator: PointRuleOperator.completed,
      points: 2,
      sortOrder: 2,
    );
    final first = await rules.create(
      userId: userId,
      habitId: habitId,
      operator: PointRuleOperator.eq,
      valueMin: 1,
      points: -1,
      sortOrder: 1,
    );

    expect((await rules.listForHabit(userId, habitId)).map((rule) => rule.id), [
      first.id,
      later.id,
    ]);
    expect(await rules.archive(userId, first.id), isTrue);
    expect(await rules.listForHabit(userId, habitId), hasLength(1));
    expect(
      await rules.listForHabit(userId, habitId, includeArchived: true),
      hasLength(2),
    );
    expect((await rules.getById(userId, first.id))?.archivedAt, isNotNull);

    final archive =
        await (database.select(database.syncQueue)..where(
              (row) =>
                  row.entityId.equals(first.id) &
                  row.operation.equals('archive'),
            ))
            .getSingle();
    expect(archive.userId, userId);
  });

  test('accepts every valid operator and value combination', () async {
    final inputs =
        <({PointRuleOperator operator, double? valueMin, double? valueMax})>[
          (
            operator: PointRuleOperator.completed,
            valueMin: null,
            valueMax: null,
          ),
          (operator: PointRuleOperator.eq, valueMin: 1, valueMax: null),
          (operator: PointRuleOperator.lt, valueMin: 2, valueMax: null),
          (operator: PointRuleOperator.lte, valueMin: 3, valueMax: null),
          (operator: PointRuleOperator.gt, valueMin: 4, valueMax: null),
          (operator: PointRuleOperator.gte, valueMin: 5, valueMax: null),
          (operator: PointRuleOperator.between, valueMin: 1, valueMax: 2),
        ];

    for (final input in inputs) {
      await rules.create(
        userId: userId,
        habitId: habitId,
        operator: input.operator,
        valueMin: input.valueMin,
        valueMax: input.valueMax,
        points: 0,
      );
    }

    expect(await rules.listForHabit(userId, habitId), hasLength(inputs.length));
  });

  test('rejects invalid operator and value combinations', () async {
    Future<void> expectInvalid({
      required PointRuleOperator operator,
      double? valueMin,
      double? valueMax,
    }) async {
      await expectLater(
        rules.create(
          userId: userId,
          habitId: habitId,
          operator: operator,
          valueMin: valueMin,
          valueMax: valueMax,
          points: 1,
        ),
        throwsArgumentError,
      );
    }

    await expectInvalid(operator: PointRuleOperator.completed, valueMin: 1);
    await expectInvalid(operator: PointRuleOperator.eq);
    await expectInvalid(
      operator: PointRuleOperator.lt,
      valueMin: 1,
      valueMax: 2,
    );
    await expectInvalid(operator: PointRuleOperator.between, valueMin: 1);
    await expectInvalid(
      operator: PointRuleOperator.between,
      valueMin: 3,
      valueMax: 2,
    );
    await expectInvalid(operator: PointRuleOperator.gte, valueMin: double.nan);
  });

  test('repository isolates users and enforces habit ownership', () async {
    final rule = await rules.create(
      userId: userId,
      habitId: habitId,
      operator: PointRuleOperator.completed,
      points: 1,
    );

    expect(await rules.getById(otherUserId, rule.id), isNull);
    expect(await rules.listForHabit(otherUserId, habitId), isEmpty);
    expect(await rules.archive(otherUserId, rule.id), isFalse);
    expect(
      await rules.update(
        userId: otherUserId,
        id: rule.id,
        habitId: otherHabitId,
        operator: PointRuleOperator.completed,
        valueMin: null,
        valueMax: null,
        points: 10,
        sortOrder: 0,
      ),
      isNull,
    );
    await expectLater(
      rules.create(
        userId: userId,
        habitId: otherHabitId,
        operator: PointRuleOperator.completed,
        points: 1,
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
  String name,
) async =>
    (await database
            .into(database.habits)
            .insertReturning(
              HabitsCompanion.insert(
                userId: userId,
                name: name,
                measurementType: MeasurementType.yesNo,
              ),
            ))
        .id;

class _UnusedTransport implements SyncTransport {
  const _UnusedTransport();

  @override
  Future<void> send(SyncQueueData item) => throw UnimplementedError();
}
