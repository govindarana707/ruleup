import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/database/database_provider.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/check_ins/data/check_in_repository.dart';
import 'package:ruleup/features/points/data/point_ledger_repository_provider.dart';

final checkInRepositoryProvider = Provider<CheckInRepository>((ref) {
  return CheckInRepository(
    ref.watch(databaseProvider),
    ref.watch(syncServiceProvider),
    pointLedger: ref.watch(pointLedgerRepositoryProvider),
  );
});
