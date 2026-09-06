import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/database/database_provider.dart';
import 'package:ruleup/features/points/data/missed_check_in_penalty_service.dart';
import 'package:ruleup/features/points/data/point_ledger_repository_provider.dart';

final missedCheckInPenaltyServiceProvider =
    Provider<MissedCheckInPenaltyService>((ref) {
      return MissedCheckInPenaltyService(
        ref.watch(databaseProvider),
        ref.watch(pointLedgerRepositoryProvider),
      );
    });
