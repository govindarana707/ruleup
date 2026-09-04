import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/database/app_database.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase.defaults();
  ref.onDispose(database.close);
  return database;
});
