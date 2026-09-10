import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/presentation/sync_status_banner.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/habits/domain/measurement_type.dart';
import 'package:ruleup/features/habits/presentation/habit_editor_screen.dart';
import 'package:ruleup/features/habits/presentation/habit_management_provider.dart';
import 'package:ruleup/features/home/presentation/home_dashboard_theme.dart';

class HabitListScreen extends ConsumerStatefulWidget {
  const HabitListScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<HabitListScreen> createState() => _HabitListScreenState();
}

class _HabitListScreenState extends ConsumerState<HabitListScreen> {
  var _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(habitCatalogProvider(widget.userId));
    final sync = ref.watch(syncControllerProvider);
    final health = ref.watch(backendHealthProvider);

    return Theme(
      data: HomeDashboardTheme.create(),
      child: Scaffold(
        key: const Key('habit-list-screen'),
        backgroundColor: HomeDashboardTheme.background,
        floatingActionButton: FloatingActionButton.extended(
          key: const Key('create-habit-button'),
          onPressed: catalog.hasValue
              ? () => _openEditor(catalog.requireValue)
              : null,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add habit'),
          backgroundColor: HomeDashboardTheme.mint,
          foregroundColor: const Color(0xFF052019),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              await ref
                  .read(syncControllerProvider.notifier)
                  .synchronize(widget.userId);
              ref.invalidate(habitCatalogProvider(widget.userId));
            },
            child: CustomScrollView(
              key: const Key('habit-list-scroll'),
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _ListHeader(
                    showArchived: _showArchived,
                    onChanged: (value) => setState(() => _showArchived = value),
                  ),
                ),
                if (health.hasError ||
                    sync.status == SyncStatus.syncing ||
                    sync.status == SyncStatus.failed)
                  SliverToBoxAdapter(
                    child: SyncStatusBanner(
                      offline: health.hasError,
                      sync: sync,
                      offlineMessage: 'Offline — changes stay safely on this device until sync returns.',
                      syncingMessage: 'Syncing your habits…',
                      failedMessage: 'Some habit changes are waiting to sync.',
                      onRetry: () => ref
                          .read(syncControllerProvider.notifier)
                          .retryFailed(widget.userId),
                      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    ),
                  ),
                switch (catalog) {
                  AsyncData(:final value) => _habitSliver(value),
                  AsyncError() => SliverFillRemaining(
                    hasScrollBody: false,
                    child: _ErrorState(
                      onRetry: () =>
                          ref.invalidate(habitCatalogProvider(widget.userId)),
                    ),
                  ),
                  _ => const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                },
                const SliverToBoxAdapter(child: SizedBox(height: 112)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _habitSliver(HabitCatalog catalog) {
    final visible = catalog.habits
        .where((habit) => habit.archived == _showArchived)
        .toList(growable: false);
    if (visible.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyState(archived: _showArchived),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      sliver: SliverList.separated(
        itemCount: visible.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final habit = visible[index];
          return _HabitCard(
            habit: habit,
            onEdit: habit.archived
                ? null
                : () => _openEditor(catalog, habitId: habit.id),
            onArchive: habit.archived
                ? () => _restore(habit)
                : () => _confirmArchive(habit),
          );
        },
      ),
    );
  }

  Future<void> _openEditor(HabitCatalog catalog, {String? habitId}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => HabitEditorScreen(
          userId: widget.userId,
          habitId: habitId,
          initialCategories: catalog.categories,
        ),
      ),
    );
    if (saved == true) {
      ref.invalidate(habitCatalogProvider(widget.userId));
      ref.invalidate(syncControllerProvider);
    }
  }

  Future<void> _confirmArchive(HabitListEntry habit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive habit?'),
        content: Text(
          '${habit.name} will leave your active list. Its history and points stay intact.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-archive-button'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _mutate(
      () => ref.read(habitArchiveActionProvider)(widget.userId, habit.id),
      '${habit.name} archived',
    );
  }

  Future<void> _restore(HabitListEntry habit) => _mutate(
    () => ref.read(habitRestoreActionProvider)(widget.userId, habit.id),
    '${habit.name} restored',
  );

  Future<void> _mutate(Future<void> Function() action, String success) async {
    try {
      await action();
      ref.invalidate(habitCatalogProvider(widget.userId));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(success)));
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_friendlyError(error))));
      }
    }
  }
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.showArchived, required this.onChanged});

  final bool showArchived;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Habits', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 16),
          _CatalogSwitch(showArchived: showArchived, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _CatalogSwitch extends StatelessWidget {
  const _CatalogSwitch({required this.showArchived, required this.onChanged});

  final bool showArchived;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: HomeDashboardTheme.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HomeDashboardTheme.outline),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _CatalogSwitchItem(
              label: 'Active',
              selected: !showArchived,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _CatalogSwitchItem(
              label: 'Archived',
              selected: showArchived,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogSwitchItem extends StatelessWidget {
  const _CatalogSwitchItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: '$label habits',
      child: Material(
        color: selected ? const Color(0xFF193C32) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected
                      ? HomeDashboardTheme.mint
                      : HomeDashboardTheme.mutedText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HabitCard extends StatelessWidget {
  const _HabitCard({
    required this.habit,
    required this.onEdit,
    required this.onArchive,
  });

  final HabitListEntry habit;
  final VoidCallback? onEdit;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        key: Key('habit-tile-${habit.id}'),
        borderRadius: BorderRadius.circular(18),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HabitIcon(type: habit.measurementType),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          habit.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 19,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          habit.categoryName ?? 'Uncategorized',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: HomeDashboardTheme.mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (habit.currentStreak > 0)
                    _StreakPill(days: habit.currentStreak),
                  const SizedBox(width: 2),
                  PopupMenuButton<String>(
                    tooltip: 'Habit actions',
                    onSelected: (_) => onArchive(),
                    iconColor: HomeDashboardTheme.mutedText,
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: habit.archived ? 'restore' : 'archive',
                        child: Text(habit.archived ? 'Restore' : 'Archive'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetaChip(
                    icon: Icons.straighten_rounded,
                    label: _measurementLabel(habit.measurementType),
                  ),
                  _MetaChip(
                    icon: Icons.calendar_today_outlined,
                    label: habit.scheduleSummary,
                  ),
                  _MetaChip(
                    icon: habit.reminderTime == null
                        ? Icons.notifications_off_outlined
                        : Icons.notifications_active_outlined,
                    label: habit.reminderTime ?? 'No reminder',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(
                    Icons.local_fire_department_outlined,
                    size: 18,
                    color: habit.currentStreak > 0
                        ? const Color(0xFFFFB83E)
                        : HomeDashboardTheme.mutedText,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    habit.currentStreak == 1
                        ? '1 day streak'
                        : '${habit.currentStreak} day streak',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: habit.currentStreak > 0
                          ? const Color(0xFFFFC35C)
                          : HomeDashboardTheme.mutedText,
                    ),
                  ),
                  const Spacer(),
                  if (onEdit != null)
                    TextButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit'),
                      style: TextButton.styleFrom(
                        foregroundColor: HomeDashboardTheme.mint,
                        minimumSize: const Size(48, 40),
                      ),
                    )
                  else
                    Text(
                      'Archived',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: HomeDashboardTheme.mutedText,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HabitIcon extends StatelessWidget {
  const _HabitIcon({required this.type});

  final MeasurementType type;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: const Color(0xFF12392F),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        _measurementIcon(type),
        color: HomeDashboardTheme.mint,
        size: 25,
      ),
    );
  }
}

class _StreakPill extends StatelessWidget {
  const _StreakPill({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF3A3020),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_fire_department_outlined,
            size: 15,
            color: Color(0xFFFFB83E),
          ),
          const SizedBox(width: 3),
          Text(
            '${days}d',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: const Color(0xFFFFC35C),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: HomeDashboardTheme.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HomeDashboardTheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: HomeDashboardTheme.mutedText),
          const SizedBox(width: 5),
          Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: HomeDashboardTheme.mutedText),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.archived});

  final bool archived;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  archived ? Icons.inventory_2_outlined : Icons.eco_outlined,
                  size: 42,
                  color: HomeDashboardTheme.mint,
                ),
                const SizedBox(height: 14),
                Text(
                  archived ? 'No archived habits' : 'Start with one habit',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 7),
                Text(
                  archived
                      ? 'Archived habits stay here with their history intact.'
                      : 'Add a small routine you can return to every day.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 38),
                const SizedBox(height: 12),
                Text(
                  "Couldn't load your habits",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

IconData _measurementIcon(MeasurementType type) => switch (type) {
  MeasurementType.yesNo => Icons.check_circle_outline,
  MeasurementType.duration => Icons.timer_outlined,
  MeasurementType.count => Icons.pin_outlined,
  MeasurementType.value => Icons.analytics_outlined,
};

String _measurementLabel(MeasurementType type) => switch (type) {
  MeasurementType.yesNo => 'Yes / No',
  MeasurementType.duration => 'Duration',
  MeasurementType.count => 'Count',
  MeasurementType.value => 'Value',
};

String _friendlyError(Object error) {
  final message = error.toString().replaceFirst('ArgumentError: ', '');
  return message.length <= 180 ? message : '${message.substring(0, 177)}…';
}
