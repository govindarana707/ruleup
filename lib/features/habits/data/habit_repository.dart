import 'package:drift/drift.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/database/tables/habits.dart';
import 'package:ruleup/core/sync/sync_service.dart';
import 'package:ruleup/features/reminders/domain/habit_reminder_rescheduler.dart';

class HabitRepository {
  HabitRepository(this._database, this._sync, [this._reminderRescheduler]);

  final AppDatabase _database;
  final SyncService _sync;
  final HabitReminderRescheduler? _reminderRescheduler;

  Future<Habit> create({
    required String userId,
    required String name,
    required MeasurementType measurementType,
    String? categoryId,
    int sortOrder = 0,
    bool missedPenaltyEnabled = false,
    int missedPenaltyPoints = 0,
  }) => _database.transaction(() async {
    await _verifyCategory(userId, categoryId);
    _validateMissedPenalty(missedPenaltyPoints);
    final habit = await _database
        .into(_database.habits)
        .insertReturning(
          HabitsCompanion.insert(
            userId: userId,
            categoryId: Value(categoryId),
            name: _validName(name),
            measurementType: measurementType,
            sortOrder: Value(sortOrder),
            missedPenaltyEnabled: Value(missedPenaltyEnabled),
            missedPenaltyPoints: Value(missedPenaltyPoints),
          ),
        );
    await _enqueue(habit, 'create');
    return habit;
  });

  Future<Habit?> getById(String userId, String id) {
    final query = _database.select(_database.habits)
      ..where((row) => row.id.equals(id) & row.userId.equals(userId));
    return query.getSingleOrNull();
  }

  Future<List<Habit>> list(String userId, {bool includeArchived = false}) {
    final query = _database.select(_database.habits)
      ..where(
        (row) =>
            row.userId.equals(userId) &
            (includeArchived ? const Constant(true) : row.archivedAt.isNull()),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.sortOrder),
        (row) => OrderingTerm.asc(row.name),
        (row) => OrderingTerm.asc(row.createdAt),
      ]);
    return query.get();
  }

  Future<Habit?> update({
    required String userId,
    required String id,
    required String name,
    required MeasurementType measurementType,
    required String? categoryId,
    required int sortOrder,
    bool? missedPenaltyEnabled,
    int? missedPenaltyPoints,
  }) => _database.transaction(() async {
    final existing = await getById(userId, id);
    if (existing == null) return null;
    await _verifyCategory(userId, categoryId);
    final updatedPenaltyPoints =
        missedPenaltyPoints ?? existing.missedPenaltyPoints;
    _validateMissedPenalty(updatedPenaltyPoints);
    await (_database.update(
      _database.habits,
    )..where((row) => row.id.equals(id) & row.userId.equals(userId))).write(
      HabitsCompanion(
        categoryId: Value(categoryId),
        name: Value(_validName(name)),
        measurementType: Value(measurementType),
        sortOrder: Value(sortOrder),
        missedPenaltyEnabled: Value(
          missedPenaltyEnabled ?? existing.missedPenaltyEnabled,
        ),
        missedPenaltyPoints: Value(updatedPenaltyPoints),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
    final updated = await getById(userId, id);
    await _enqueue(updated!, 'update');
    return updated;
  });

  Future<bool> archive(String userId, String id) async {
    final archived = await _database.transaction(() async {
      final existing = await getById(userId, id);
      if (existing == null) return false;
      if (existing.archivedAt != null) return true;
      final now = DateTime.now().toUtc();
      await (_database.update(
        _database.habits,
      )..where((row) => row.id.equals(id) & row.userId.equals(userId))).write(
        HabitsCompanion(archivedAt: Value(now), updatedAt: Value(now)),
      );
      await _enqueue(existing, 'archive');
      return true;
    });
    if (archived) await _safeReschedule(userId, id);
    return archived;
  }

  Future<bool> restore(String userId, String id) async {
    final restored = await _database.transaction(() async {
      final existing = await getById(userId, id);
      if (existing == null) return false;
      if (existing.archivedAt == null) return true;
      final now = DateTime.now().toUtc();
      await (_database.update(
        _database.habits,
      )..where((row) => row.id.equals(id) & row.userId.equals(userId))).write(
        HabitsCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
      );
      final updated = await getById(userId, id);
      await _enqueue(updated!, 'update');
      return true;
    });
    if (restored) await _safeReschedule(userId, id);
    return restored;
  }

  Future<void> _verifyCategory(String userId, String? categoryId) async {
    if (categoryId == null) return;
    final category =
        await (_database.select(_database.categories)..where(
              (row) => row.id.equals(categoryId) & row.userId.equals(userId),
            ))
            .getSingleOrNull();
    if (category == null) {
      throw ArgumentError.value(categoryId, 'categoryId');
    }
  }

  Future<void> _enqueue(Habit habit, String operation) => _sync.enqueue(
    userId: habit.userId,
    entityType: 'habit',
    entityId: habit.id,
    operation: operation,
  );

  String _validName(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) throw ArgumentError.value(name, 'name');
    return normalized;
  }

  void _validateMissedPenalty(int points) {
    if (points > 0) {
      throw ArgumentError.value(
        points,
        'missedPenaltyPoints',
        'Must be zero or negative',
      );
    }
  }

  Future<void> _safeReschedule(String userId, String habitId) async {
    try {
      await _reminderRescheduler?.rescheduleHabit(userId, habitId);
    } on Object {
      // Habit persistence is independent from notification availability.
    }
  }
}
