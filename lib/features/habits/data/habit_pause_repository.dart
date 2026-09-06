import 'package:drift/drift.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/database/habit_date_converter.dart';
import 'package:ruleup/core/sync/sync_service.dart';
import 'package:ruleup/core/utils/habit_date.dart';
import 'package:ruleup/features/reminders/domain/habit_reminder_rescheduler.dart';

class HabitPauseRepository {
  HabitPauseRepository(this._database, this._sync, [this._reminderRescheduler]);

  final AppDatabase _database;
  final SyncService _sync;
  final HabitReminderRescheduler? _reminderRescheduler;

  Future<HabitPause> create({
    required String userId,
    required String habitId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final pause = await _database.transaction(() async {
      await _verifyHabit(userId, habitId);
      final dates = _validRange(startDate, endDate);
      await _ensureNoOverlap(userId, habitId, dates.$1, dates.$2);
      final created = await _database
          .into(_database.habitPauses)
          .insertReturning(
            HabitPausesCompanion.insert(
              userId: userId,
              habitId: habitId,
              startDate: dates.$1,
              endDate: dates.$2,
            ),
          );
      await _enqueue(created, 'create');
      return created;
    });
    await _safeReschedule(userId, habitId);
    return pause;
  }

  Future<HabitPause?> getById(String userId, String id) {
    final query = _database.select(_database.habitPauses)
      ..where((row) => row.id.equals(id) & row.userId.equals(userId));
    return query.getSingleOrNull();
  }

  Future<List<HabitPause>> listForHabit(String userId, String habitId) {
    final query = _database.select(_database.habitPauses)
      ..where((row) => row.userId.equals(userId) & row.habitId.equals(habitId))
      ..orderBy([
        (row) => OrderingTerm.asc(row.startDate),
        (row) => OrderingTerm.asc(row.endDate),
        (row) => OrderingTerm.asc(row.id),
      ]);
    return query.get();
  }

  Future<HabitPause?> update({
    required String userId,
    required String id,
    required String habitId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    String? previousHabitId;
    final pause = await _database.transaction(() async {
      final existing = await getById(userId, id);
      if (existing == null) return null;
      previousHabitId = existing.habitId;
      await _verifyHabit(userId, habitId);
      final dates = _validRange(startDate, endDate);
      await _ensureNoOverlap(
        userId,
        habitId,
        dates.$1,
        dates.$2,
        excludingId: id,
      );
      await (_database.update(
        _database.habitPauses,
      )..where((row) => row.id.equals(id) & row.userId.equals(userId))).write(
        HabitPausesCompanion(
          habitId: Value(habitId),
          startDate: Value(dates.$1),
          endDate: Value(dates.$2),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      final updated = await getById(userId, id);
      await _enqueue(updated!, 'update');
      return updated;
    });
    if (pause != null) {
      await _safeReschedule(userId, previousHabitId!);
      if (habitId != previousHabitId) await _safeReschedule(userId, habitId);
    }
    return pause;
  }

  Future<bool> delete(String userId, String id) async {
    String? habitId;
    final deleted = await _database.transaction(() async {
      final existing = await getById(userId, id);
      if (existing == null) return false;
      habitId = existing.habitId;
      await (_database.delete(
        _database.habitPauses,
      )..where((row) => row.id.equals(id) & row.userId.equals(userId))).go();
      await _enqueue(existing, 'delete');
      return true;
    });
    if (habitId != null) await _safeReschedule(userId, habitId!);
    return deleted;
  }

  Future<void> _verifyHabit(String userId, String habitId) async {
    final habit =
        await (_database.select(_database.habits)..where(
              (row) => row.id.equals(habitId) & row.userId.equals(userId),
            ))
            .getSingleOrNull();
    if (habit == null) throw ArgumentError.value(habitId, 'habitId');
  }

  (DateTime, DateTime) _validRange(DateTime startDate, DateTime endDate) {
    final start = normalizeHabitDate(startDate);
    final end = normalizeHabitDate(endDate);
    if (end.isBefore(start)) {
      throw ArgumentError.value(
        endDate,
        'endDate',
        'Must be on or after start',
      );
    }
    return (start, end);
  }

  Future<void> _ensureNoOverlap(
    String userId,
    String habitId,
    DateTime startDate,
    DateTime endDate, {
    String? excludingId,
  }) async {
    final converter = const HabitDateConverter();
    final query = _database.select(_database.habitPauses)
      ..where(
        (row) =>
            row.userId.equals(userId) &
            row.habitId.equals(habitId) &
            row.startDate.isSmallerOrEqualValue(converter.toSql(endDate)) &
            row.endDate.isBiggerOrEqualValue(converter.toSql(startDate)) &
            (excludingId == null
                ? const Constant(true)
                : row.id.equals(excludingId).not()),
      )
      ..limit(1);
    if (await query.getSingleOrNull() != null) {
      throw OverlappingHabitPauseException(habitId, startDate, endDate);
    }
  }

  Future<void> _enqueue(HabitPause pause, String operation) => _sync.enqueue(
    userId: pause.userId,
    entityType: 'habit_pause',
    entityId: pause.id,
    operation: operation,
  );

  Future<void> _safeReschedule(String userId, String habitId) async {
    try {
      await _reminderRescheduler?.rescheduleHabit(userId, habitId);
    } on Object {
      // Pause persistence is independent from notification availability.
    }
  }
}

class OverlappingHabitPauseException implements Exception {
  const OverlappingHabitPauseException(
    this.habitId,
    this.startDate,
    this.endDate,
  );

  final String habitId;
  final DateTime startDate;
  final DateTime endDate;
}
