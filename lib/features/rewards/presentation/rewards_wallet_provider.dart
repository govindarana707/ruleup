import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/points/data/point_ledger_repository.dart';
import 'package:ruleup/features/points/data/point_ledger_repository_provider.dart';
import 'package:ruleup/features/rewards/data/reward_repository.dart';
import 'package:ruleup/features/rewards/data/reward_repository_provider.dart';

final rewardsWalletCoordinatorProvider = Provider<RewardsWalletCoordinator>(
  (ref) => RewardsWalletCoordinator(
    rewards: ref.watch(rewardRepositoryProvider),
    ledger: ref.watch(pointLedgerRepositoryProvider),
  ),
);

final rewardsWalletProvider = FutureProvider.family<RewardsWalletData, String>((
  ref,
  userId,
) async {
  ref.watch(syncControllerProvider.select((state) => state.status));
  return ref.watch(rewardsWalletCoordinatorProvider).load(userId);
});

typedef RewardSaveAction = Future<String> Function(
  String userId,
  RewardDraft draft,
);
typedef RewardMutationAction = Future<void> Function(
  String userId,
  String rewardId,
);

final rewardSaveActionProvider = Provider<RewardSaveAction>(
  (ref) => ref.watch(rewardsWalletCoordinatorProvider).save,
);
final rewardArchiveActionProvider = Provider<RewardMutationAction>(
  (ref) => ref.watch(rewardsWalletCoordinatorProvider).archive,
);
final rewardRestoreActionProvider = Provider<RewardMutationAction>(
  (ref) => ref.watch(rewardsWalletCoordinatorProvider).restore,
);
final rewardRedeemActionProvider = Provider<RewardMutationAction>(
  (ref) => ref.watch(rewardsWalletCoordinatorProvider).redeem,
);

class RewardsWalletCoordinator {
  const RewardsWalletCoordinator({required this.rewards, required this.ledger});

  final RewardRepository rewards;
  final PointLedgerRepository ledger;

  Future<RewardsWalletData> load(String userId) async {
    final wallet = await ledger.getWallet(userId);
    final rows = await rewards.list(userId, includeArchived: true);
    return RewardsWalletData(
      availablePoints: wallet.availablePoints,
      lifetimeEarned: wallet.lifetimeEarned,
      spentPoints: wallet.spentPoints,
      rewards: rows
          .map(
            (row) => RewardListItem(
              id: row.id,
              name: row.name,
              pointsCost: row.pointsCost,
              monetaryCap: row.monetaryCap,
              sortOrder: row.sortOrder,
              archived: row.archivedAt != null,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<String> save(String userId, RewardDraft draft) async {
    final error = draft.validate();
    if (error != null) throw ArgumentError(error);
    final pointsCost = int.parse(draft.pointsCost.trim());
    final monetaryCap = draft.monetaryCap.trim().isEmpty
        ? null
        : double.parse(draft.monetaryCap.trim());
    if (draft.id == null) {
      final active = await rewards.list(userId);
      final nextOrder = active.isEmpty
          ? 0
          : active
                    .map((reward) => reward.sortOrder)
                    .reduce((a, b) => a > b ? a : b) +
                1;
      final created = await rewards.create(
        userId: userId,
        name: draft.name,
        pointsCost: pointsCost,
        monetaryCap: monetaryCap,
        sortOrder: nextOrder,
      );
      draft.id = created.id;
      draft.sortOrder = created.sortOrder;
      return created.id;
    }
    final updated = await rewards.update(
      userId: userId,
      id: draft.id!,
      name: draft.name,
      pointsCost: pointsCost,
      monetaryCap: monetaryCap,
      sortOrder: draft.sortOrder,
    );
    if (updated == null) throw StateError('Reward not found');
    return updated.id;
  }

  Future<void> archive(String userId, String rewardId) async {
    if (!await rewards.archive(userId, rewardId)) {
      throw StateError('Reward not found');
    }
  }

  Future<void> restore(String userId, String rewardId) async {
    if (!await rewards.restore(userId, rewardId)) {
      throw StateError('Reward not found');
    }
  }

  Future<void> redeem(String userId, String rewardId) async {
    await rewards.redeem(userId: userId, rewardId: rewardId);
  }
}

class RewardsWalletData {
  const RewardsWalletData({
    required this.availablePoints,
    required this.lifetimeEarned,
    required this.spentPoints,
    required this.rewards,
  });

  final int availablePoints;
  final int lifetimeEarned;
  final int spentPoints;
  final List<RewardListItem> rewards;
}

class RewardListItem {
  const RewardListItem({
    required this.id,
    required this.name,
    required this.pointsCost,
    required this.sortOrder,
    required this.archived,
    this.monetaryCap,
  });

  final String id;
  final String name;
  final int pointsCost;
  final double? monetaryCap;
  final int sortOrder;
  final bool archived;

  RewardDraft toDraft() => RewardDraft(
    id: id,
    name: name,
    pointsCost: pointsCost.toString(),
    monetaryCap: monetaryCap?.toString() ?? '',
    sortOrder: sortOrder,
  );
}

class RewardDraft {
  RewardDraft({
    this.id,
    this.name = '',
    this.pointsCost = '',
    this.monetaryCap = '',
    this.sortOrder = 0,
  });

  String? id;
  String name;
  String pointsCost;
  String monetaryCap;
  int sortOrder;

  String? validate() {
    if (name.trim().isEmpty) return 'Enter a reward name.';
    final cost = int.tryParse(pointsCost.trim());
    if (cost == null || cost <= 0) {
      return 'Points cost must be a positive whole number.';
    }
    if (monetaryCap.trim().isNotEmpty) {
      final cap = double.tryParse(monetaryCap.trim());
      if (cap == null || !cap.isFinite || cap < 0) {
        return 'Monetary cap must be zero or a positive number.';
      }
    }
    return null;
  }
}
