import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/presentation/sync_status_banner.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/home/presentation/home_dashboard_provider.dart';
import 'package:ruleup/features/rewards/presentation/reward_editor_dialog.dart';
import 'package:ruleup/features/rewards/presentation/rewards_wallet_provider.dart';

class RewardsWalletScreen extends ConsumerStatefulWidget {
  const RewardsWalletScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<RewardsWalletScreen> createState() =>
      _RewardsWalletScreenState();
}

class _RewardsWalletScreenState extends ConsumerState<RewardsWalletScreen> {
  var _showArchived = false;
  final _busyRewardIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(rewardsWalletProvider(widget.userId));
    final health = ref.watch(backendHealthProvider);
    final sync = ref.watch(syncControllerProvider);
    return Scaffold(
      key: const Key('rewards-wallet-screen'),
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create-reward-button'),
        onPressed: wallet.hasValue ? () => _editReward() : null,
        icon: const Icon(Icons.add),
        label: const Text('New reward'),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await ref
                .read(syncControllerProvider.notifier)
                .synchronize(widget.userId);
            ref.invalidate(rewardsWalletProvider(widget.userId));
          },
          child: CustomScrollView(
            key: const Key('rewards-wallet-scroll'),
            slivers: [
              SliverToBoxAdapter(child: _header(wallet.asData?.value)),
              if (health.hasError ||
                  sync.status == SyncStatus.syncing ||
                  sync.status == SyncStatus.failed)
                SliverToBoxAdapter(
                  child: SyncStatusBanner(
                    offline: health.hasError,
                    sync: sync,
                    offlineMessage: 'Offline — reward changes stay local until sync returns.',
                    syncingMessage: 'Syncing rewards and wallet…',
                    failedMessage: 'Some reward changes are waiting to sync.',
                    onRetry: () => ref
                        .read(syncControllerProvider.notifier)
                        .retryFailed(widget.userId),
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  ),
                ),
              switch (wallet) {
                AsyncData(:final value) => _rewardsSliver(value),
                AsyncError() => SliverFillRemaining(
                  hasScrollBody: false,
                  child: _ErrorState(
                    onRetry: () =>
                        ref.invalidate(rewardsWalletProvider(widget.userId)),
                  ),
                ),
                _ => const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                ),
              },
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(RewardsWalletData? wallet) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Rewards', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          const Text('Turn steady progress into something meaningful.'),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 620
                  ? (constraints.maxWidth - 24) / 3
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  _WalletMetric(
                    width: width,
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Available points',
                    value: wallet?.availablePoints.toString() ?? '—',
                    emphasized: true,
                  ),
                  _WalletMetric(
                    width: width,
                    icon: Icons.trending_up,
                    label: 'Lifetime earned',
                    value: wallet?.lifetimeEarned.toString() ?? '—',
                  ),
                  _WalletMetric(
                    width: width,
                    icon: Icons.redeem_outlined,
                    label: 'Spent points',
                    value: wallet?.spentPoints.toString() ?? '—',
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              Text(
                _showArchived ? 'Archived rewards' : 'Your rewards',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Active')),
                  ButtonSegment(value: true, label: Text('Archived')),
                ],
                selected: {_showArchived},
                onSelectionChanged: (value) =>
                    setState(() => _showArchived = value.first),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rewardsSliver(RewardsWalletData wallet) {
    final visible = wallet.rewards
        .where((reward) => reward.archived == _showArchived)
        .toList(growable: false);
    if (visible.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyState(archived: _showArchived),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      sliver: SliverList.separated(
        itemCount: visible.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final reward = visible[index];
          final affordable = wallet.availablePoints >= reward.pointsCost;
          return _RewardCard(
            reward: reward,
            affordable: affordable,
            pointsNeeded: (reward.pointsCost - wallet.availablePoints).clamp(
              0,
              reward.pointsCost,
            ),
            busy: _busyRewardIds.contains(reward.id),
            onEdit: reward.archived ? null : () => _editReward(reward),
            onArchive: reward.archived
                ? () => _restore(reward)
                : () => _confirmArchive(reward),
            onRedeem: reward.archived || !affordable
                ? null
                : () => _confirmRedeem(wallet, reward),
          );
        },
      ),
    );
  }

  Future<void> _editReward([RewardListItem? reward]) async {
    final draft = await showDialog<RewardDraft>(
      context: context,
      builder: (_) =>
          RewardEditorDialog(draft: reward?.toDraft() ?? RewardDraft()),
    );
    if (draft == null || !mounted) return;
    try {
      await ref.read(rewardSaveActionProvider)(widget.userId, draft);
      _refresh();
      if (mounted) {
        _showFeedback(reward == null ? 'Reward created' : 'Reward updated');
      }
    } on Object catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _confirmArchive(RewardListItem reward) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive reward?'),
        content: Text(
          '${reward.name} will leave your active rewards. Past redemptions remain unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-archive-reward-button'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _mutate(
        reward.id,
        () => ref.read(rewardArchiveActionProvider)(widget.userId, reward.id),
        '${reward.name} archived',
      );
    }
  }

  Future<void> _restore(RewardListItem reward) => _mutate(
    reward.id,
    () => ref.read(rewardRestoreActionProvider)(widget.userId, reward.id),
    '${reward.name} restored',
  );

  Future<void> _confirmRedeem(
    RewardsWalletData wallet,
    RewardListItem reward,
  ) async {
    final remaining = wallet.availablePoints - reward.pointsCost;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Redeem reward?'),
        content: Text(
          '${reward.name} costs ${reward.pointsCost} points. '
          'You’ll have $remaining points remaining.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-redeem-button'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Redeem'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _mutate(
      reward.id,
      () => ref.read(rewardRedeemActionProvider)(widget.userId, reward.id),
      '${reward.name} redeemed for ${reward.pointsCost} points',
      refreshDashboard: true,
    );
  }

  Future<void> _mutate(
    String rewardId,
    Future<void> Function() action,
    String success, {
    bool refreshDashboard = false,
  }) async {
    setState(() => _busyRewardIds.add(rewardId));
    try {
      await action();
      _refresh();
      if (refreshDashboard) {
        ref.invalidate(homeDashboardProvider(widget.userId));
      }
      if (mounted) _showFeedback(success);
    } on Object catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busyRewardIds.remove(rewardId));
    }
  }

  void _refresh() => ref.invalidate(rewardsWalletProvider(widget.userId));

  void _showFeedback(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('reward-success-feedback'),
        content: Text(message),
      ),
    );
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(_friendlyError(error))));
  }
}

class _WalletMetric extends StatelessWidget {
  const _WalletMetric({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Card(
        color: emphasized ? scheme.primaryContainer : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: emphasized ? scheme.onPrimaryContainer : null),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RewardCard extends StatelessWidget {
  const _RewardCard({
    required this.reward,
    required this.affordable,
    required this.pointsNeeded,
    required this.busy,
    required this.onEdit,
    required this.onArchive,
    required this.onRedeem,
  });

  final RewardListItem reward;
  final bool affordable;
  final int pointsNeeded;
  final bool busy;
  final VoidCallback? onEdit;
  final VoidCallback onArchive;
  final VoidCallback? onRedeem;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        key: Key('reward-card-${reward.id}'),
        onTap: onEdit,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: affordable
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHighest,
                    foregroundColor: affordable
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                    child: const Icon(Icons.redeem_outlined),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reward.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${reward.pointsCost} points',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(color: scheme.primary),
                        ),
                        if (reward.monetaryCap != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            'Monetary cap ${_numberLabel(reward.monetaryCap!)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 7),
                        Text(
                          affordable
                              ? 'Ready to redeem'
                              : '$pointsNeeded points to go',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Reward actions',
                    onSelected: (_) => onArchive(),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: reward.archived ? 'restore' : 'archive',
                        child: Text(reward.archived ? 'Restore' : 'Archive'),
                      ),
                    ],
                  ),
                ],
              ),
              if (!reward.archived)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonal(
                      key: Key('redeem-reward-${reward.id}'),
                      onPressed: busy ? null : onRedeem,
                      child: busy
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Redeem'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.archived});

  final bool archived;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            archived ? Icons.inventory_2_outlined : Icons.redeem_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            archived
                ? 'No archived rewards'
                : 'Create a reward worth working toward',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            archived
                ? 'Archived rewards remain available here.'
                : 'Keep it personal, realistic, and motivating.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, size: 44),
        const SizedBox(height: 12),
        Text(
          "Couldn't load rewards",
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}

String _numberLabel(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);

String _friendlyError(Object error) {
  final message = error.toString().replaceFirst('ArgumentError: ', '');
  return message.length <= 180 ? message : '${message.substring(0, 177)}…';
}
