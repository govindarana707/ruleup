import 'package:drift/drift.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/sync/sync_service.dart';

class HabitOptionRepository {
  HabitOptionRepository(this._database, this._sync);

  final AppDatabase _database;
  final SyncService _sync;

  Future<HabitOption> create({
    required String userId,
    required String habitId,
    required String label,
    double? numericValue,
    int sortOrder = 0,
  }) => _database.transaction(() async {
    await _verifyHabit(userId, habitId);
    final option = await _database
        .into(_database.habitOptions)
        .insertReturning(
          HabitOptionsCompanion.insert(
            userId: userId,
            habitId: habitId,
            label: _validLabel(label),
            numericValue: Value(numericValue),
            sortOrder: Value(sortOrder),
          ),
        );
    await _enqueue(option, 'create');
    return option;
  });

  Future<HabitOption?> getById(String userId, String id) {
    final query = _database.select(_database.habitOptions)
      ..where((row) => row.id.equals(id) & row.userId.equals(userId));
    return query.getSingleOrNull();
  }

  Future<List<HabitOption>> listForHabit(
    String userId,
    String habitId, {
    bool includeArchived = false,
  }) {
    final query = _database.select(_database.habitOptions)
      ..where(
        (row) =>
            row.userId.equals(userId) &
            row.habitId.equals(habitId) &
            (includeArchived ? const Constant(true) : row.archivedAt.isNull()),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.sortOrder),
        (row) => OrderingTerm.asc(row.label),
        (row) => OrderingTerm.asc(row.createdAt),
      ]);
    return query.get();
  }

  Future<HabitOption?> update({
    required String userId,
    required String id,
    required String habitId,
    required String label,
    required double? numericValue,
    required int sortOrder,
  }) => _database.transaction(() async {
    final existing = await getById(userId, id);
    if (existing == null) return null;
    await _verifyHabit(userId, habitId);
    await (_database.update(
      _database.habitOptions,
    )..where((row) => row.id.equals(id) & row.userId.equals(userId))).write(
      HabitOptionsCompanion(
        habitId: Value(habitId),
        label: Value(_validLabel(label)),
        numericValue: Value(numericValue),
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
          _database.habitOptions,
        )..where((row) => row.id.equals(id) & row.userId.equals(userId))).write(
          HabitOptionsCompanion(archivedAt: Value(now), updatedAt: Value(now)),
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

  Future<void> _enqueue(HabitOption option, String operation) => _sync.enqueue(
    userId: option.userId,
    entityType: 'habit_option',
    entityId: option.id,
    operation: operation,
  );

  String _validLabel(String label) {
    final normalized = label.trim();
    if (normalized.isEmpty) throw ArgumentError.value(label, 'label');
    return normalized;
  }
}
