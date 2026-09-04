import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/database/database_provider.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/habits/data/habit_schedule_repository.dart';

final habitScheduleRepositoryProvider = Provider<HabitScheduleRepository>((
  ref,
) {
  return HabitScheduleRepository(
    ref.watch(databaseProvider),
    ref.watch(syncServiceProvider),
  );
});
