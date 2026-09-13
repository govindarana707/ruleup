import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ruleup/core/presentation/point_currency_theme.dart';
import 'package:ruleup/core/presentation/sync_status_banner.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/home/presentation/home_dashboard_provider.dart';
import 'package:ruleup/features/home/presentation/home_dashboard_theme.dart';
import 'package:ruleup/features/rewards/data/reward_image_service.dart';
import 'package:ruleup/features/rewards/presentation/reward_editor_dialog.dart';
import 'package:ruleup/features/rewards/presentation/reward_image_thumbnail.dart';
import 'package:ruleup/features/rewards/presentation/rewards_wallet_provider.dart';

final _redeemButtonStyle = FilledButton.styleFrom(
  backgroundColor: PointCurrencyTheme.gold,
  foregroundColor: PointCurrencyTheme.onGold,
  disabledBackgroundColor: HomeDashboardTheme.surfaceRaised,
  disabledForegroundColor: HomeDashboardTheme.mutedText,
);

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
                if (wallet.hasValue)
                  SliverToBoxAdapter(child: _addRewardButton()),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(RewardsWalletData? wallet) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _RewardsHeader(),
        const SizedBox(height: 24),
        _WalletSummary(wallet: wallet, onHowItWorks: _showWalletHelp),
        const SizedBox(height: 18),
        _RewardSwitch(
          archived: _showArchived,
          activeCount:
              wallet?.rewards.where((reward) => !reward.archived).length ?? 0,
          archivedCount:
              wallet?.rewards.where((reward) => reward.archived).length ?? 0,
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
      return SliverToBoxAdapter(child: _EmptyState(archived: _showArchived));
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

  Widget _addRewardButton() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
    child: Align(
      alignment: Alignment.centerRight,
      child: FilledButton.icon(
        key: const Key('create-reward-button'),
        onPressed: () => _editReward(),
        style: FilledButton.styleFrom(
          backgroundColor: HomeDashboardTheme.mint,
          foregroundColor: const Color(0xFF052019),
          minimumSize: const Size(168, 58),
          padding: const EdgeInsets.symmetric(horizontal: 24),
        ),
        icon: const Icon(Icons.add_rounded, size: 26),
        label: const Text('Add reward'),
      ),
    ),
  );

  Future<void> _showWalletHelp() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => Theme(
      data: HomeDashboardTheme.create(),
      child: const _WalletExplanation(),
    ),
  );

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
      final rewardId = await ref.read(rewardSaveActionProvider)(
        widget.userId,
        draft,
      );
      final oldKey = reward?.imageKey;
      if (draft.selectedImage case final XFile image) {
        await ref
            .read(rewardImageServiceProvider)
            .replace(
              userId: widget.userId,
              rewardId: rewardId,
              oldKey: oldKey,
              image: image,
            );
      } else if (draft.removeImage && oldKey != null) {
        await ref
            .read(rewardImageServiceProvider)
            .remove(userId: widget.userId, rewardId: rewardId, key: oldKey);
      }
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
      rewardAction: true,
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
    Key key, {
    bool rewardAction = false,
  }) async =>
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
                style: rewardAction ? _redeemButtonStyle : null,
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

class _RewardsHeader extends StatelessWidget {
  const _RewardsHeader();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final title = Text(
        'Rewards',
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(fontSize: 38, letterSpacing: -0.9),
      );
      const pill = _RewardMantraPill();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (constraints.maxWidth >= 315)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: title),
                const SizedBox(width: 12),
                pill,
              ],
            )
          else ...[
            title,
            const SizedBox(height: 12),
            pill,
          ],
          const SizedBox(height: 4),
          Text(
            'Turn your habits into a better you.',
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: HomeDashboardTheme.mutedText),
          ),
        ],
      );
    },
  );
}

class _RewardMantraPill extends StatelessWidget {
  const _RewardMantraPill();

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('reward-mantra-pill'),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: const Color(0xFF1D1B13),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(
        color: PointCurrencyTheme.gold.withValues(alpha: 0.38),
      ),
    ),
    child: const FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.card_giftcard_rounded,
            size: 17,
            color: PointCurrencyTheme.gold,
          ),
          SizedBox(width: 7),
          Text(
            'Redeem • Grow • Repeat',
            style: TextStyle(
              color: PointCurrencyTheme.gold,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class _WalletSummary extends StatelessWidget {
  const _WalletSummary({required this.wallet, required this.onHowItWorks});

  final RewardsWalletData? wallet;
  final VoidCallback onHowItWorks;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('reward-wallet-outer-card'),
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: HomeDashboardTheme.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFF2B3D47)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x28000000),
          blurRadius: 20,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final walletTitle = Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFF332B18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: PointCurrencyTheme.gold,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your Reward Wallet',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Your points, your progress, your rewards.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            );
            final help = TextButton.icon(
              key: const Key('wallet-how-it-works'),
              onPressed: onHowItWorks,
              style: TextButton.styleFrom(
                foregroundColor: HomeDashboardTheme.mint,
                minimumSize: const Size(0, 42),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              icon: const Icon(Icons.info_outline_rounded, size: 20),
              label: const Text('How it works?'),
            );
            if (constraints.maxWidth >= 315) {
              return Row(
                children: [
                  Expanded(child: walletTitle),
                  const SizedBox(width: 8),
                  help,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                walletTitle,
                Align(alignment: Alignment.centerRight, child: help),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 10.0;
            final columns = constraints.maxWidth >= 300 ? 3 : 2;
            final cardWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                _WalletMetricCard(
                  key: const Key('available-points-card'),
                  width: cardWidth,
                  label: 'Available points',
                  value: wallet?.availablePoints.toString() ?? '—',
                  helper: 'Ready to use\non rewards',
                  accent: PointCurrencyTheme.gold,
                  iconSurface: const Color(0xFF41361D),
                  surface: const Color(0xFF211F17),
                  outline: PointCurrencyTheme.gold,
                  emphasizeValue: true,
                ),
                _WalletMetricCard(
                  key: const Key('lifetime-earned-card'),
                  width: cardWidth,
                  label: 'Lifetime earned',
                  value: wallet?.lifetimeEarned.toString() ?? '—',
                  helper: "Total points\nyou've earned",
                  accent: HomeDashboardTheme.mint,
                  iconSurface: const Color(0xFF143D34),
                  surface: const Color(0xFF102722),
                  outline: const Color(0xFF245548),
                ),
                _WalletMetricCard(
                  key: const Key('spent-points-card'),
                  width: cardWidth,
                  label: 'Spent points',
                  value: wallet?.spentPoints.toString() ?? '—',
                  helper: 'Used on\nrewards',
                  accent: const Color(0xFFA8B4B8),
                  iconSurface: const Color(0xFF27343C),
                  surface: const Color(0xFF162128),
                  outline: const Color(0xFF30434D),
                ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _WalletMetricCard extends StatelessWidget {
  const _WalletMetricCard({
    super.key,
    required this.width,
    required this.label,
    required this.value,
    required this.helper,
    required this.accent,
    required this.iconSurface,
    required this.surface,
    required this.outline,
    this.emphasizeValue = false,
  });

  final double width;
  final String label;
  final String value;
  final String helper;
  final Color accent;
  final Color iconSurface;
  final Color surface;
  final Color outline;
  final bool emphasizeValue;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    constraints: const BoxConstraints(minHeight: 154),
    padding: const EdgeInsets.fromLTRB(10, 12, 10, 11),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: emphasizeValue ? outline : outline.withValues(alpha: 0.75),
        width: emphasizeValue ? 1.4 : 1,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: iconSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(child: _FlatCoinsIcon(size: 23, color: accent)),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          maxLines: 2,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: HomeDashboardTheme.text,
            fontWeight: FontWeight.w600,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: emphasizeValue ? accent : HomeDashboardTheme.text,
            fontSize: 27,
            height: 1,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          helper,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(fontSize: 11.5, height: 1.2),
        ),
      ],
    ),
  );
}

class _WalletExplanation extends StatelessWidget {
  const _WalletExplanation();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
      child: Column(
        key: const Key('wallet-explanation'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How your wallet works',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 18),
          const _WalletHelpRow(
            color: PointCurrencyTheme.gold,
            title: 'Available points',
            description: 'Points you can spend on rewards right now.',
          ),
          const _WalletHelpRow(
            color: HomeDashboardTheme.mint,
            title: 'Lifetime earned',
            description: 'Every point you have earned from your habits.',
          ),
          const _WalletHelpRow(
            color: Color(0xFFA8B4B8),
            title: 'Spent points',
            description: 'Points already used to redeem rewards.',
          ),
        ],
      ),
    ),
  );
}

class _WalletHelpRow extends StatelessWidget {
  const _WalletHelpRow({
    required this.color,
    required this.title,
    required this.description,
  });

  final Color color;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Center(child: _FlatCoinsIcon(size: 22, color: color)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 3),
              Text(description, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
}

class _RewardSwitch extends StatelessWidget {
  const _RewardSwitch({
    required this.archived,
    required this.activeCount,
    required this.archivedCount,
    required this.onChanged,
  });

  final bool archived;
  final int activeCount;
  final int archivedCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('reward-status-switch'),
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      color: HomeDashboardTheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFF2B3D47)),
    ),
    child: Row(
      children: [
        _item(context, 'Active ($activeCount)', false),
        _item(context, 'Archived ($archivedCount)', true),
      ],
    ),
  );

  Widget _item(BuildContext context, String label, bool value) {
    final selected = archived == value;
    return Expanded(
      child: Material(
        color: selected ? const Color(0xFF19262E) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onChanged(value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 13, 8, 10),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected
                        ? PointCurrencyTheme.gold
                        : HomeDashboardTheme.mutedText,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
              AnimatedContainer(
                key: selected ? const Key('reward-status-indicator') : null,
                duration: const Duration(milliseconds: 180),
                width: selected ? 72 : 0,
                height: 3,
                decoration: BoxDecoration(
                  color: PointCurrencyTheme.gold,
                  borderRadius: BorderRadius.circular(99),
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
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: HomeDashboardTheme.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFF2B3D47)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x22000000),
          blurRadius: 16,
          offset: Offset(0, 7),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('reward-card-${reward.id}'),
        onTap: onEdit,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RewardImageThumbnail(
                    key: Key('reward-image-${reward.id}'),
                    imageKey: reward.imageKey,
                    size: 64,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reward.name,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontSize: 20),
                        ),
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            const _FlatCoinsIcon(
                              size: 20,
                              color: PointCurrencyTheme.gold,
                            ),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                '${reward.pointsCost} points',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: PointCurrencyTheme.gold,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          affordable
                              ? 'Ready to redeem'
                              : '$pointsNeeded points to go',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: affordable
                                    ? PointCurrencyTheme.gold
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
              if (reward.monetaryCap != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Monetary cap ${_numberLabel(reward.monetaryCap!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (!reward.archived)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: FilledButton(
                    key: Key('redeem-reward-${reward.id}'),
                    onPressed: busy ? null : onRedeem,
                    style: _redeemButtonStyle,
                    child: busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            affordable ? 'Redeem reward' : 'Not enough points',
                          ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _FlatCoinsIcon extends StatelessWidget {
  const _FlatCoinsIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Points',
    child: ExcludeSemantics(
      child: CustomPaint(
        key: const Key('flat-point-coins-icon'),
        size: Size.square(size),
        painter: _FlatCoinsPainter(color),
      ),
    ),
  );
}

class _FlatCoinsPainter extends CustomPainter {
  const _FlatCoinsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas.scale(scale, scale);
    final fill = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    void coin(double left, double top, double width) {
      final oval = Rect.fromLTWH(left, top, width, 4.6);
      canvas.drawOval(oval, fill);
      canvas.drawOval(oval, stroke);
      canvas.drawLine(Offset(left, top + 2.3), Offset(left, top + 6.2), stroke);
      canvas.drawLine(
        Offset(left + width, top + 2.3),
        Offset(left + width, top + 6.2),
        stroke,
      );
      canvas.drawArc(
        Rect.fromLTWH(left, top + 3.9, width, 4.6),
        0,
        3.1416,
        false,
        stroke,
      );
    }

    coin(10.5, 2.5, 9.5);
    coin(7, 8, 10.5);
    coin(3.5, 13.5, 11.5);
  }

  @override
  bool shouldRepaint(_FlatCoinsPainter oldDelegate) =>
      oldDelegate.color != color;
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
