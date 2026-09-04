import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/database/database_provider.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/categories/data/category_repository.dart';

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return CategoryRepository(
    ref.watch(databaseProvider),
    ref.watch(syncServiceProvider),
  );
});
