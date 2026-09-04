import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/database/database_provider.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/habits/data/habit_repository.dart';

final habitRepositoryProvider = Provider<HabitRepository>((ref) {
  return HabitRepository(
    ref.watch(databaseProvider),
    ref.watch(syncServiceProvider),
  );
});
