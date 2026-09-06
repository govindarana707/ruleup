import 'package:drift/drift.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/notifications/local_notification_service.dart';
import 'package:ruleup/core/utils/habit_date.dart';
import 'package:ruleup/features/habits/domain/schedule_applicability.dart';
import 'package:ruleup/features/habits/domain/streak_calculator.dart';
import 'package:ruleup/features/reminders/domain/habit_reminder_rescheduler.dart';
import 'package:ruleup/features/reminders/domain/reminder_time.dart';

class HabitReminderScheduler implements HabitReminderRescheduler {
  HabitReminderScheduler(
    this._database,
    this._notifications, {
    ScheduleApplicability? applicability,
    DateTime Function()? now,
    this.horizonDays = 30,
  }) : _applicability = applicability ?? const ScheduleApplicability(),
       _now = now ?? DateTime.now;

  final AppDatabase _database;
  final LocalNotificationService _notifications;
  final ScheduleApplicability _applicability;
  final DateTime Function() _now;
  final int horizonDays;

  @override
  Future<ReminderScheduleResult> rescheduleHabit(
    String userId,
    String habitId,
  ) async {
    try {
      final habit =
          await (_database.select(_database.habits)..where(
                (row) => row.id.equals(habitId) & row.userId.equals(userId),
              ))
              .getSingleOrNull();
      if (habit == null) {
        return const ReminderScheduleResult(
          status: ReminderScheduleStatus.inactive,
        );
      }
      final reminder =
          await (_database.select(_database.habitReminders)..where(
                (row) =>
                    row.userId.equals(userId) & row.habitId.equals(habitId),
              ))
              .getSingleOrNull();
      await _notifications.initialize();
      await _notifications.cancelHabit(habitId);
      if (habit.archivedAt != null || reminder == null || !reminder.enabled) {
        return const ReminderScheduleResult(
          status: ReminderScheduleStatus.inactive,
        );
      }
      if (!await _notifications.requestPermission()) {
        return const ReminderScheduleResult(
          status: ReminderScheduleStatus.permissionDenied,
        );
      }

      final time = ReminderTime.parse(reminder.timeOfDay);
      final schedules =
          (await (_database.select(_database.habitSchedules)..where(
                    (row) =>
                        row.userId.equals(userId) & row.habitId.equals(habitId),
                  ))
                  .get())
              .map(
                (schedule) => HabitScheduleDefinition.fromConfig(
                  type: schedule.scheduleType,
                  scheduleConfig: schedule.scheduleConfig,
                ),
              )
              .toList();
      final pauses =
          (await (_database.select(_database.habitPauses)..where(
                    (row) =>
                        row.userId.equals(userId) & row.habitId.equals(habitId),
                  ))
                  .get())
              .map(
                (pause) => HabitPausePeriod(
                  startDate: pause.startDate,
                  endDate: pause.endDate,
                ),
              )
              .toList();

      final current = _now();
      final firstDate = normalizeHabitDate(current);
      var scheduledCount = 0;
      for (var offset = 0; offset < horizonDays; offset++) {
        final date = firstDate.add(Duration(days: offset));
        if (pauses.any((pause) => pause.contains(date))) continue;
        if (!_applicability.isApplicable(
          habitDate: date,
          schedules: schedules,
        )) {
          continue;
        }
        final scheduledAt = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        );
        if (!scheduledAt.isAfter(current)) continue;
        await _notifications.scheduleHabit(
          notificationId: notificationId(habitId, date),
          habitId: habitId,
          habitName: habit.name,
          scheduledAt: scheduledAt,
        );
        scheduledCount++;
      }
      return ReminderScheduleResult(
        status: ReminderScheduleStatus.scheduled,
        scheduledCount: scheduledCount,
      );
    } on Object {
      return const ReminderScheduleResult(
        status: ReminderScheduleStatus.failed,
      );
    }
  }

  static int notificationId(String habitId, DateTime habitDate) {
    final value = '$habitId:${habitDateKey(habitDate)}';
    var hash = 0x811c9dc5;
    for (final byte in value.codeUnits) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }
}
