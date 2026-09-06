import 'package:drift/drift.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/sync/sync_service.dart';
import 'package:ruleup/features/reminders/domain/habit_reminder_rescheduler.dart';
import 'package:ruleup/features/reminders/domain/reminder_time.dart';

class HabitReminderRepository {
  HabitReminderRepository(this._database, this._sync, [this._rescheduler]);

  final AppDatabase _database;
  final SyncService _sync;
  final HabitReminderRescheduler? _rescheduler;

  Future<HabitReminder> create({
    required String userId,
    required String habitId,
    required bool enabled,
    required String timeOfDay,
  }) async {
    final reminder = await _database.transaction(() async {
      await _verifyHabit(userId, habitId);
      final existing = await getForHabit(userId, habitId);
      if (existing != null) {
        throw StateError('A reminder already exists for this habit');
      }
      final created = await _database
          .into(_database.habitReminders)
          .insertReturning(
            HabitRemindersCompanion.insert(
              userId: userId,
              habitId: habitId,
              enabled: Value(enabled),
              timeOfDay: ReminderTime.parse(timeOfDay).value,
            ),
          );
      await _enqueue(created, 'create');
      return created;
    });
    await _safeReschedule(userId, habitId);
    return reminder;
  }

  Future<HabitReminder?> getById(String userId, String id) {
    final query = _database.select(_database.habitReminders)
      ..where((row) => row.id.equals(id) & row.userId.equals(userId));
    return query.getSingleOrNull();
  }

  Future<HabitReminder?> getForHabit(String userId, String habitId) {
    final query = _database.select(_database.habitReminders)
      ..where((row) => row.userId.equals(userId) & row.habitId.equals(habitId));
    return query.getSingleOrNull();
  }

  Future<List<HabitReminder>> list(String userId) {
    final query = _database.select(_database.habitReminders)
      ..where((row) => row.userId.equals(userId))
      ..orderBy([
        (row) => OrderingTerm.asc(row.createdAt),
        (row) => OrderingTerm.asc(row.id),
      ]);
    return query.get();
  }

  Future<HabitReminder?> update({
    required String userId,
    required String id,
    required bool enabled,
    required String timeOfDay,
  }) async {
    final reminder = await _database.transaction(() async {
      final existing = await getById(userId, id);
      if (existing == null) return null;
      await (_database.update(
        _database.habitReminders,
      )..where((row) => row.id.equals(id) & row.userId.equals(userId))).write(
        HabitRemindersCompanion(
          enabled: Value(enabled),
          timeOfDay: Value(ReminderTime.parse(timeOfDay).value),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      final updated = await getById(userId, id);
      await _enqueue(updated!, 'update');
      return updated;
    });
    if (reminder != null) {
      await _safeReschedule(userId, reminder.habitId);
    }
    return reminder;
  }

  Future<bool> delete(String userId, String id) async {
    String? habitId;
    final deleted = await _database.transaction(() async {
      final existing = await getById(userId, id);
      if (existing == null) return false;
      habitId = existing.habitId;
      await (_database.delete(
        _database.habitReminders,
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

  Future<void> _enqueue(HabitReminder reminder, String operation) =>
      _sync.enqueue(
        userId: reminder.userId,
        entityType: 'habit_reminder',
        entityId: reminder.id,
        operation: operation,
      );

  Future<void> _safeReschedule(String userId, String habitId) async {
    try {
      await _rescheduler?.rescheduleHabit(userId, habitId);
    } on Object {
      // Notification failures must not roll back local reminder data.
    }
  }
}
