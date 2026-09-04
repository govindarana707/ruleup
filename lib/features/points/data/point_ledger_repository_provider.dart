import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/database/database_provider.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/points/data/point_ledger_repository.dart';

final pointLedgerRepositoryProvider = Provider<PointLedgerRepository>((ref) {
  return PointLedgerRepository(
    ref.watch(databaseProvider),
    ref.watch(syncServiceProvider),
  );
});
