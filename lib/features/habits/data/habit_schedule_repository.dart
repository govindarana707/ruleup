import 'package:drift/drift.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/database/tables/habit_schedules.dart';
import 'package:ruleup/core/sync/sync_service.dart';
import 'package:ruleup/features/habits/domain/schedule_applicability.dart';

class HabitScheduleRepository {
  HabitScheduleRepository(this._database, this._sync);

  final AppDatabase _database;
  final SyncService _sync;

  Future<HabitSchedule> create({
    required String userId,
    required String habitId,
    required ScheduleType scheduleType,
    required String scheduleConfig,
  }) => _database.transaction(() async {
    await _verifyHabit(userId, habitId);
    final schedule = await _database
        .into(_database.habitSchedules)
        .insertReturning(
          HabitSchedulesCompanion.insert(
            userId: userId,
            habitId: habitId,
            scheduleType: scheduleType,
            scheduleConfig: _validConfig(scheduleType, scheduleConfig),
          ),
        );
    await _enqueue(schedule, 'create');
    return schedule;
  });

  Future<HabitSchedule?> getById(String userId, String id) {
    final query = _database.select(_database.habitSchedules)
      ..where((row) => row.id.equals(id) & row.userId.equals(userId));
    return query.getSingleOrNull();
  }

  Future<List<HabitSchedule>> listForHabit(String userId, String habitId) {
    final query = _database.select(_database.habitSchedules)
      ..where((row) => row.userId.equals(userId) & row.habitId.equals(habitId))
      ..orderBy([
        (row) => OrderingTerm.asc(row.createdAt),
        (row) => OrderingTerm.asc(row.id),
      ]);
    return query.get();
  }

  Future<HabitSchedule?> update({
    required String userId,
    required String id,
    required String habitId,
    required ScheduleType scheduleType,
    required String scheduleConfig,
  }) => _database.transaction(() async {
    final existing = await getById(userId, id);
    if (existing == null) return null;
    await _verifyHabit(userId, habitId);
    await (_database.update(
      _database.habitSchedules,
    )..where((row) => row.id.equals(id) & row.userId.equals(userId))).write(
      HabitSchedulesCompanion(
        habitId: Value(habitId),
        scheduleType: Value(scheduleType),
        scheduleConfig: Value(_validConfig(scheduleType, scheduleConfig)),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
    final updated = await getById(userId, id);
    await _enqueue(updated!, 'update');
    return updated;
  });

  Future<bool> delete(String userId, String id) =>
      _database.transaction(() async {
        final existing = await getById(userId, id);
        if (existing == null) return false;
        await (_database.delete(
          _database.habitSchedules,
        )..where((row) => row.id.equals(id) & row.userId.equals(userId))).go();
        await _enqueue(existing, 'delete');
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

  Future<void> _enqueue(HabitSchedule schedule, String operation) =>
      _sync.enqueue(
        userId: schedule.userId,
        entityType: 'habit_schedule',
        entityId: schedule.id,
        operation: operation,
      );

  String _validConfig(ScheduleType scheduleType, String scheduleConfig) {
    final normalized = scheduleConfig.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(scheduleConfig, 'scheduleConfig');
    }
    HabitScheduleDefinition.fromConfig(
      type: scheduleType,
      scheduleConfig: normalized,
    );
    return normalized;
  }
}
