import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/presentation/sync_status_banner.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/home/presentation/home_dashboard_provider.dart';
import 'package:ruleup/features/home/presentation/home_dashboard_theme.dart';
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
    return Theme(
      data: HomeDashboardTheme.create(),
      child: Scaffold(
        key: const Key('rewards-wallet-screen'),
        backgroundColor: HomeDashboardTheme.background,
        floatingActionButton: FloatingActionButton.extended(
          key: const Key('create-reward-button'),
          onPressed: wallet.hasValue ? () => _editReward() : null,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add reward'),
          backgroundColor: HomeDashboardTheme.mint,
          foregroundColor: const Color(0xFF052019),
          elevation: 0,
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              await ref
                  .read(syncControllerProvider.notifier)
                  .synchronize(widget.userId);
              ref.invalidate(rewardsWalletProvider(widget.userId));
            },
            child: CustomScrollView(
              key: const Key('rewards-wallet-scroll'),
              physics: const AlwaysScrollableScrollPhysics(),
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
                      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
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
      ),
    );
  }

  Widget _header(RewardsWalletData? wallet) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Rewards', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        _WalletSummary(wallet: wallet),
        const SizedBox(height: 16),
        _RewardSwitch(
          archived: _showArchived,
          onChanged: (value) => setState(() => _showArchived = value),
        ),
      ],
    ),
  );

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
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      sliver: SliverList.separated(
        itemCount: visible.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
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
      builder: (_) => Theme(
        data: HomeDashboardTheme.create(),
        child: RewardEditorDialog(draft: reward?.toDraft() ?? RewardDraft()),
      ),
    );
    if (draft == null || !mounted) return;
    try {
      await ref.read(rewardSaveActionProvider)(widget.userId, draft);
      _refresh();
      if (mounted) {
        _feedback(reward == null ? 'Reward created' : 'Reward updated');
      }
    } on Object catch (error) {
      if (mounted) _error(error);
    }
  }

  Future<void> _confirmArchive(RewardListItem reward) async {
    final ok = await _confirm(
      'Archive reward?',
      '${reward.name} will leave your active rewards. Past redemptions remain unchanged.',
      'Archive',
      const Key('confirm-archive-reward-button'),
    );
    if (ok && mounted) {
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
    final ok = await _confirm(
      'Redeem reward?',
      '${reward.name} costs ${reward.pointsCost} points. You’ll have ${wallet.availablePoints - reward.pointsCost} points remaining.',
      'Redeem',
      const Key('confirm-redeem-button'),
    );
    if (ok && mounted) {
      await _mutate(
        reward.id,
        () => ref.read(rewardRedeemActionProvider)(widget.userId, reward.id),
        '${reward.name} redeemed for ${reward.pointsCost} points',
        refreshDashboard: true,
      );
    }
  }

  Future<bool> _confirm(
    String title,
    String content,
    String action,
    Key key,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => Theme(
          data: HomeDashboardTheme.create(),
          child: AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: key,
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
        ),
      ) ??
      false;
  Future<void> _mutate(
    String id,
    Future<void> Function() action,
    String success, {
    bool refreshDashboard = false,
  }) async {
    setState(() => _busyRewardIds.add(id));
    try {
      await action();
      _refresh();
      if (refreshDashboard) {
        ref.invalidate(homeDashboardProvider(widget.userId));
      }
      if (mounted) _feedback(success);
    } on Object catch (error) {
      if (mounted) _error(error);
    } finally {
      if (mounted) setState(() => _busyRewardIds.remove(id));
    }
  }

  void _refresh() => ref.invalidate(rewardsWalletProvider(widget.userId));
  void _feedback(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(key: const Key('reward-success-feedback'), content: Text(message)),
  );
  void _error(Object error) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_friendlyError(error))));
}

class _WalletSummary extends StatelessWidget {
  const _WalletSummary({this.wallet});
  final RewardsWalletData? wallet;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: HomeDashboardTheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: HomeDashboardTheme.outline),
    ),
    child: LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth > 430;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _metric(
              context,
              'Available points',
              wallet?.availablePoints.toString() ?? '—',
              Icons.account_balance_wallet_outlined,
              HomeDashboardTheme.mint,
              wide ? (c.maxWidth - 28) / 3 : (c.maxWidth - 14) / 2,
            ),
            _metric(
              context,
              'Lifetime earned',
              wallet?.lifetimeEarned.toString() ?? '—',
              Icons.trending_up_rounded,
              HomeDashboardTheme.text,
              wide ? (c.maxWidth - 28) / 3 : (c.maxWidth - 14) / 2,
            ),
            _metric(
              context,
              'Spent points',
              wallet?.spentPoints.toString() ?? '—',
              Icons.redeem_outlined,
              HomeDashboardTheme.mutedText,
              wide ? (c.maxWidth - 28) / 3 : (c.maxWidth - 14) / 2,
            ),
          ],
        );
      },
    ),
  );
  Widget _metric(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
    double width,
  ) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(color: color),
        ),
        const SizedBox(height: 2),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    ),
  );
}

class _RewardSwitch extends StatelessWidget {
  const _RewardSwitch({required this.archived, required this.onChanged});
  final bool archived;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: HomeDashboardTheme.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: HomeDashboardTheme.outline),
    ),
    child: Row(
      children: [
        _item(context, 'Active', false),
        _item(context, 'Archived', true),
      ],
    ),
  );
  Widget _item(BuildContext context, String label, bool value) {
    final selected = archived == value;
    return Expanded(
      child: Material(
        color: selected ? const Color(0xFF193C32) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onChanged(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: selected
                    ? HomeDashboardTheme.mint
                    : HomeDashboardTheme.mutedText,
              ),
            ),
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
  Widget build(BuildContext context) => Card(
    child: InkWell(
      key: Key('reward-card-${reward.id}'),
      onTap: onEdit,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: affordable
                        ? const Color(0xFF173C32)
                        : HomeDashboardTheme.surfaceRaised,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.card_giftcard_rounded,
                    color: affordable
                        ? HomeDashboardTheme.mint
                        : HomeDashboardTheme.mutedText,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reward.name,
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontSize: 19),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${reward.pointsCost} points',
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(color: HomeDashboardTheme.mint),
                      ),
                      if (reward.monetaryCap != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            'Monetary cap ${_numberLabel(reward.monetaryCap!)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      const SizedBox(height: 7),
                      Text(
                        affordable
                            ? 'Ready to redeem'
                            : '$pointsNeeded points to go',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: affordable
                                  ? HomeDashboardTheme.mint
                                  : HomeDashboardTheme.mutedText,
                            ),
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
                padding: const EdgeInsets.only(top: 14),
                child: FilledButton(
                  key: Key('redeem-reward-${reward.id}'),
                  onPressed: busy ? null : onRedeem,
                  child: busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(affordable ? 'Redeem' : 'Not enough points'),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.archived});
  final bool archived;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: HomeDashboardTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: HomeDashboardTheme.outline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              archived
                  ? Icons.inventory_2_outlined
                  : Icons.card_giftcard_outlined,
              size: 44,
              color: HomeDashboardTheme.mutedText,
            ),
            const SizedBox(height: 14),
            Text(
              archived
                  ? 'No archived rewards'
                  : 'Create a reward worth working toward',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 7),
            Text(
              archived
                  ? 'Archived rewards remain available here.'
                  : 'Keep it personal, realistic, and motivating.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: HomeDashboardTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: HomeDashboardTheme.outline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 44,
              color: HomeDashboardTheme.mutedText,
            ),
            const SizedBox(height: 12),
            Text(
              "Couldn't load rewards",
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
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
