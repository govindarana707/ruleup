import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/database/database_provider.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/habits/data/habit_schedule_repository.dart';
import 'package:ruleup/features/reminders/data/habit_reminder_scheduler_provider.dart';

final habitScheduleRepositoryProvider = Provider<HabitScheduleRepository>((
  ref,
) {
  return HabitScheduleRepository(
    ref.watch(databaseProvider),
    ref.watch(syncServiceProvider),
    ref.watch(habitReminderSchedulerProvider),
  );
});
