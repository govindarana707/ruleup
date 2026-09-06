abstract interface class HabitReminderRescheduler {
  Future<ReminderScheduleResult> rescheduleHabit(String userId, String habitId);
}

enum ReminderScheduleStatus { scheduled, inactive, permissionDenied, failed }

class ReminderScheduleResult {
  const ReminderScheduleResult({required this.status, this.scheduledCount = 0});

  final ReminderScheduleStatus status;
  final int scheduledCount;
}
