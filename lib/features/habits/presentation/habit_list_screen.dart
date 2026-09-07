import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/presentation/sync_status_banner.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/habits/domain/measurement_type.dart';
import 'package:ruleup/features/habits/presentation/habit_editor_screen.dart';
import 'package:ruleup/features/habits/presentation/habit_management_provider.dart';

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
    return Scaffold(
      key: const Key('habit-list-screen'),
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create-habit-button'),
        onPressed: catalog.hasValue
            ? () => _openEditor(catalog.requireValue)
            : null,
        icon: const Icon(Icons.add),
        label: const Text('New habit'),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await ref
                .read(syncControllerProvider.notifier)
                .synchronize(widget.userId);
            ref.invalidate(habitCatalogProvider(widget.userId));
          },
          child: CustomScrollView(
            key: const Key('habit-list-scroll'),
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
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      sliver: SliverList.separated(
        itemCount: visible.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final habit = visible[index];
          return _HabitTile(
            habit: habit,
            onTap: habit.archived
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Habits', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(
                'Build routines that fit your real week.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Active')),
              ButtonSegment(value: true, label: Text('Archived')),
            ],
            selected: {showArchived},
            onSelectionChanged: (value) => onChanged(value.first),
          ),
        ],
      ),
    );
  }
}

class _HabitTile extends StatelessWidget {
  const _HabitTile({
    required this.habit,
    required this.onTap,
    required this.onArchive,
  });

  final HabitListEntry habit;
  final VoidCallback? onTap;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        key: Key('habit-tile-${habit.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: colorScheme.secondaryContainer,
                foregroundColor: colorScheme.onSecondaryContainer,
                child: Icon(_measurementIcon(habit.measurementType)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            habit.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (habit.currentStreak > 0)
                          _MetaChip(
                            icon: Icons.local_fire_department_outlined,
                            label: '${habit.currentStreak}d',
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _MetaChip(
                          icon: Icons.folder_outlined,
                          label: habit.categoryName ?? 'Uncategorized',
                        ),
                        _MetaChip(
                          icon: Icons.straighten,
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
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Habit actions',
                onSelected: (_) => onArchive(),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: habit.archived ? 'restore' : 'archive',
                    child: Text(habit.archived ? 'Restore' : 'Archive'),
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

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              archived ? Icons.inventory_2_outlined : Icons.track_changes,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              archived
                  ? 'No archived habits'
                  : 'Start with one meaningful habit',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              archived
                  ? 'Habits you archive will remain available here.'
                  : 'Choose something small enough to repeat consistently.',
              textAlign: TextAlign.center,
            ),
          ],
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44),
            const SizedBox(height: 12),
            Text(
              "Couldn't load your habits",
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
