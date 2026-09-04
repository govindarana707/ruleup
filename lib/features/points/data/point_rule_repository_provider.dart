import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/database/database_provider.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/points/data/point_rule_repository.dart';

final pointRuleRepositoryProvider = Provider<PointRuleRepository>((ref) {
  return PointRuleRepository(
    ref.watch(databaseProvider),
    ref.watch(syncServiceProvider),
  );
});
