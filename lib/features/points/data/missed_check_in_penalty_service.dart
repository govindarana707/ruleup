import 'package:drift/drift.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/utils/habit_date.dart';
import 'package:ruleup/features/habits/domain/schedule_applicability.dart';
import 'package:ruleup/features/habits/domain/streak_calculator.dart';
import 'package:ruleup/features/points/data/point_ledger_repository.dart';

class MissedCheckInPenaltyService {
  MissedCheckInPenaltyService(
    this._database,
    this._ledger, {
    ScheduleApplicability? applicability,
    DateTime Function()? now,
  }) : _applicability = applicability ?? const ScheduleApplicability(),
       _now = now ?? DateTime.now;

  final AppDatabase _database;
  final PointLedgerRepository _ledger;
  final ScheduleApplicability _applicability;
  final DateTime Function() _now;

  Future<int> generateForHabit({
    required String userId,
    required String habitId,
    required DateTime startDate,
    DateTime? currentHabitDate,
  }) => _database.transaction(() async {
    final habit =
        await (_database.select(_database.habits)..where(
              (row) => row.id.equals(habitId) & row.userId.equals(userId),
            ))
            .getSingleOrNull();
    if (habit == null) throw ArgumentError.value(habitId, 'habitId');
    if (!habit.missedPenaltyEnabled) return 0;
    if (habit.missedPenaltyPoints > 0) {
      throw StateError('Stored missed penalty points must not be positive');
    }

    final firstDate = normalizeHabitDate(startDate);
    final currentDate = normalizeHabitDate(currentHabitDate ?? _now());
    if (!firstDate.isBefore(currentDate)) return 0;

    final storedSchedules =
        await (_database.select(_database.habitSchedules)..where(
              (row) => row.userId.equals(userId) & row.habitId.equals(habitId),
            ))
            .get();
    final schedules = storedSchedules
        .map(
          (schedule) => HabitScheduleDefinition.fromConfig(
            type: schedule.scheduleType,
            scheduleConfig: schedule.scheduleConfig,
          ),
        )
        .toList();
    final storedPauses =
        await (_database.select(_database.habitPauses)..where(
              (row) => row.userId.equals(userId) & row.habitId.equals(habitId),
            ))
            .get();
    final pauses = storedPauses
        .map(
          (pause) => HabitPausePeriod(
            startDate: pause.startDate,
            endDate: pause.endDate,
          ),
        )
        .toList();
    final completedDates =
        (await (_database.select(_database.checkIns)..where(
                  (row) =>
                      row.userId.equals(userId) & row.habitId.equals(habitId),
                ))
                .get())
            .map((checkIn) => habitDateKey(checkIn.habitDate))
            .toSet();

    var createdCount = 0;
    for (
      var date = firstDate;
      date.isBefore(currentDate);
      date = date.add(const Duration(days: 1))
    ) {
      if (pauses.any((pause) => pause.contains(date))) continue;
      if (!_applicability.isApplicable(habitDate: date, schedules: schedules)) {
        continue;
      }
      if (completedDates.contains(habitDateKey(date))) continue;
      if (await _ledger.getForMissedCheckIn(userId, habitId, date) != null) {
        continue;
      }
      await _ledger.createMissedCheckInPenalty(
        userId: userId,
        habitId: habitId,
        habitDate: date,
        points: habit.missedPenaltyPoints,
      );
      createdCount++;
    }
    return createdCount;
  });
}
