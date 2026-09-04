import 'package:drift/drift.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/database/tables/point_rules.dart';
import 'package:ruleup/core/sync/sync_service.dart';

class PointRuleRepository {
  PointRuleRepository(this._database, this._sync);

  final AppDatabase _database;
  final SyncService _sync;

  Future<PointRule> create({
    required String userId,
    required String habitId,
    required PointRuleOperator operator,
    required int points,
    double? valueMin,
    double? valueMax,
    int sortOrder = 0,
  }) => _database.transaction(() async {
    await _verifyHabit(userId, habitId);
    _validateValues(operator, valueMin, valueMax);
    final rule = await _database
        .into(_database.pointRules)
        .insertReturning(
          PointRulesCompanion.insert(
            userId: userId,
            habitId: habitId,
            operator: operator,
            valueMin: Value(valueMin),
            valueMax: Value(valueMax),
            points: points,
            sortOrder: Value(sortOrder),
          ),
        );
    await _enqueue(rule, 'create');
    return rule;
  });

  Future<PointRule?> getById(String userId, String id) {
    final query = _database.select(_database.pointRules)
      ..where((row) => row.id.equals(id) & row.userId.equals(userId));
    return query.getSingleOrNull();
  }

  Future<List<PointRule>> listForHabit(
    String userId,
    String habitId, {
    bool includeArchived = false,
  }) {
    final query = _database.select(_database.pointRules)
      ..where(
        (row) =>
            row.userId.equals(userId) &
            row.habitId.equals(habitId) &
            (includeArchived ? const Constant(true) : row.archivedAt.isNull()),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.sortOrder),
        (row) => OrderingTerm.asc(row.createdAt),
        (row) => OrderingTerm.asc(row.id),
      ]);
    return query.get();
  }

  Future<PointRule?> update({
    required String userId,
    required String id,
    required String habitId,
    required PointRuleOperator operator,
    required double? valueMin,
    required double? valueMax,
    required int points,
    required int sortOrder,
  }) => _database.transaction(() async {
    final existing = await getById(userId, id);
    if (existing == null) return null;
    await _verifyHabit(userId, habitId);
    _validateValues(operator, valueMin, valueMax);
    await (_database.update(
      _database.pointRules,
    )..where((row) => row.id.equals(id) & row.userId.equals(userId))).write(
      PointRulesCompanion(
        habitId: Value(habitId),
        operator: Value(operator),
        valueMin: Value(valueMin),
        valueMax: Value(valueMax),
        points: Value(points),
        sortOrder: Value(sortOrder),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
    final updated = await getById(userId, id);
    await _enqueue(updated!, 'update');
    return updated;
  });

  Future<bool> archive(String userId, String id) =>
      _database.transaction(() async {
        final existing = await getById(userId, id);
        if (existing == null) return false;
        if (existing.archivedAt != null) return true;
        final now = DateTime.now().toUtc();
        await (_database.update(
          _database.pointRules,
        )..where((row) => row.id.equals(id) & row.userId.equals(userId))).write(
          PointRulesCompanion(archivedAt: Value(now), updatedAt: Value(now)),
        );
        await _enqueue(existing, 'archive');
        return true;
      });

  Future<void> _verifyHabit(String userId, String habitId) async {
    final habit =
        await (_database.select(_database.habits)..where(
              (row) => row.id.equals(habitId) & row.userId.equals(userId),
            ))
            .getSingleOrNull();
    if (habit == null) throw ArgumentError.value(habitId, 'habitId');
  }

  void _validateValues(
    PointRuleOperator operator,
    double? valueMin,
    double? valueMax,
  ) {
    if (valueMin != null && !valueMin.isFinite) {
      throw ArgumentError.value(valueMin, 'valueMin', 'Must be finite');
    }
    if (valueMax != null && !valueMax.isFinite) {
      throw ArgumentError.value(valueMax, 'valueMax', 'Must be finite');
    }

    switch (operator) {
      case PointRuleOperator.completed:
        if (valueMin != null || valueMax != null) {
          throw ArgumentError(
            'completed rules must not define valueMin or valueMax',
          );
        }
      case PointRuleOperator.between:
        if (valueMin == null || valueMax == null || valueMin > valueMax) {
          throw ArgumentError(
            'between rules require valueMin and valueMax with min <= max',
          );
        }
      case PointRuleOperator.eq:
      case PointRuleOperator.lt:
      case PointRuleOperator.lte:
      case PointRuleOperator.gt:
      case PointRuleOperator.gte:
        if (valueMin == null || valueMax != null) {
          throw ArgumentError(
            '${operator.name} rules require valueMin and no valueMax',
          );
        }
    }
  }

  Future<void> _enqueue(PointRule rule, String operation) => _sync.enqueue(
    userId: rule.userId,
    entityType: 'point_rule',
    entityId: rule.id,
    operation: operation,
  );
}
