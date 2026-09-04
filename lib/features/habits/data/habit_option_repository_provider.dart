import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/database/database_provider.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/habits/data/habit_option_repository.dart';

final habitOptionRepositoryProvider = Provider<HabitOptionRepository>((ref) {
  return HabitOptionRepository(
    ref.watch(databaseProvider),
    ref.watch(syncServiceProvider),
  );
});
