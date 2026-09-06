import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/database/database_provider.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/habits/data/habit_pause_repository.dart';

final habitPauseRepositoryProvider = Provider<HabitPauseRepository>((ref) {
  return HabitPauseRepository(
    ref.watch(databaseProvider),
    ref.watch(syncServiceProvider),
  );
});
