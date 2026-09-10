import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/presentation/sync_status_banner.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/core/utils/habit_date.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/history/presentation/history_provider.dart';
import 'package:ruleup/features/home/presentation/home_dashboard_theme.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late DateTime _selectedDate;
  String? _habitId;
  var _completionFilter = HistoryCompletionFilter.all;

  HistoryQuery get _query => (userId: widget.userId, date: _selectedDate);

  @override
  void initState() {
    super.initState();
    _selectedDate = normalizeHabitDate(ref.read(historyNowProvider));
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyDayProvider(_query));
    final health = ref.watch(backendHealthProvider);
    final sync = ref.watch(syncControllerProvider);
    final today = normalizeHabitDate(ref.watch(historyNowProvider));
    return Theme(
      data: HomeDashboardTheme.create(),
      child: Scaffold(
        key: const Key('history-screen'),
        backgroundColor: HomeDashboardTheme.background,
        body: SafeArea(
          top: true,
          child: RefreshIndicator(
            onRefresh: () async {
              await ref
                  .read(syncControllerProvider.notifier)
                  .synchronize(widget.userId);
              ref.invalidate(historyDayProvider(_query));
            },
            child: CustomScrollView(
              key: const Key('history-scroll'),
              slivers: [
                SliverToBoxAdapter(
                  child: _HistoryHeader(
                    data: history.asData?.value,
                    selectedDate: _selectedDate,
                    today: today,
                    onDateChanged: (date) {
                      setState(() => _selectedDate = normalizeHabitDate(date));
                    },
                  ),
                ),
                if (health.hasError ||
                    sync.status == SyncStatus.syncing ||
                    sync.status == SyncStatus.failed)
                  SliverToBoxAdapter(
                    child: SyncStatusBanner(
                      offline: health.hasError,
                      sync: sync,
                      offlineMessage:
                          'Offline — showing history stored on this device.',
                      syncingMessage: 'Syncing your history…',
                      failedMessage:
                          'Some history changes are waiting to sync.',
                      onRetry: () => ref
                          .read(syncControllerProvider.notifier)
                          .retryFailed(widget.userId),
                      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    ),
                  ),
                if (history.hasValue)
                  SliverToBoxAdapter(child: _filters(history.requireValue)),
                switch (history) {
                  AsyncData(:final value) => _entriesSliver(value),
                  AsyncError() => SliverFillRemaining(
                    hasScrollBody: false,
                    child: _ErrorState(
                      onRetry: () => ref.invalidate(historyDayProvider(_query)),
                    ),
                  ),
                  _ => const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                },
                const SliverToBoxAdapter(child: SizedBox(height: 28)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filters(HistoryDayData data) {
    final effectiveHabit = data.habits.any((habit) => habit.id == _habitId)
        ? _habitId
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String?>(
            key: const Key('history-habit-filter'),
            initialValue: effectiveHabit,
            decoration: _historyInputDecoration(
              labelText: 'Habit',
              prefixIcon: Icon(Icons.filter_alt_outlined),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('All habits')),
              ...data.habits.map(
                (habit) =>
                    DropdownMenuItem(value: habit.id, child: Text(habit.name)),
              ),
            ],
            onChanged: (value) => setState(() => _habitId = value),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<HistoryCompletionFilter>(
              segments: const [
                ButtonSegment(
                  value: HistoryCompletionFilter.all,
                  label: Text('All states'),
                ),
                ButtonSegment(
                  value: HistoryCompletionFilter.completed,
                  label: Text('Completed'),
                ),
                ButtonSegment(
                  value: HistoryCompletionFilter.missed,
                  label: Text('Missed'),
                ),
              ],
              selected: {_completionFilter},
              onSelectionChanged: (value) =>
                  setState(() => _completionFilter = value.first),
            ),
          ),
        ],
      ),
    );
  }

  Widget _entriesSliver(HistoryDayData data) {
    final effectiveHabit = data.habits.any((habit) => habit.id == _habitId)
        ? _habitId
        : null;
    final entries = data.entries
        .where((entry) {
          if (effectiveHabit != null && entry.habitId != effectiveHabit) {
            return false;
          }
          return switch (_completionFilter) {
            HistoryCompletionFilter.all => true,
            HistoryCompletionFilter.completed =>
              entry.status == HistoryEntryStatus.completed,
            HistoryCompletionFilter.missed =>
              entry.status == HistoryEntryStatus.missed,
          };
        })
        .toList(growable: false);
    if (entries.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyState(filtered: data.entries.isNotEmpty),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList.separated(
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final entry = entries[index];
          return _HistoryEntryCard(
            entry: entry,
            onTap: () => _showDetails(entry),
          );
        },
      ),
    );
  }

  Future<void> _showDetails(HistoryEntry entry) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: HomeDashboardTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _HistoryDetails(entry: entry, date: _selectedDate),
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({
    required this.data,
    required this.selectedDate,
    required this.today,
    required this.onDateChanged,
  });

  final HistoryDayData? data;
  final DateTime selectedDate;
  final DateTime today;
  final ValueChanged<DateTime> onDateChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('History', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StreakCard(
                  label: 'Current streak',
                  value: data?.currentStreak,
                  icon: Icons.local_fire_department_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StreakCard(
                  label: 'Longest streak',
                  value: data?.longestStreak,
                  icon: Icons.emoji_events_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Card(
            clipBehavior: Clip.antiAlias,
            child: CalendarDatePicker(
              key: const Key('history-calendar'),
              initialDate: selectedDate,
              firstDate: DateTime(today.year - 5),
              lastDate: today,
              onDateChanged: onDateChanged,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              _dateHeading(selectedDate),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int? value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                Text(
                  value == null ? '—' : '$value days',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _HistoryEntryCard extends StatelessWidget {
  const _HistoryEntryCard({required this.entry, required this.onTap});

  final HistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = _statusVisual(entry.status, Theme.of(context).colorScheme);
    return Card(
      child: InkWell(
        key: Key('history-entry-${entry.habitId}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: visual.background,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(visual.icon, color: visual.foreground),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.habitName,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontSize: 19),
                          ),
                        ),
                        _StatusPill(label: visual.label, visual: visual),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${entry.categoryName ?? 'Uncategorized'} · ${entry.scheduleSummary}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (entry.status == HistoryEntryStatus.completed) ...[
                      const SizedBox(height: 7),
                      Text(_completionSummary(entry)),
                    ],
                    if (entry.points != 0) ...[
                      const SizedBox(height: 5),
                      Text(
                        _pointsLabel(entry.points),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: entry.points > 0
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.visual});

  final String label;
  final _StatusVisual visual;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: visual.background,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: visual.foreground),
    ),
  );
}

class _HistoryDetails extends StatelessWidget {
  const _HistoryDetails({required this.entry, required this.date});

  final HistoryEntry entry;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final visual = _statusVisual(entry.status, Theme.of(context).colorScheme);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          key: const Key('history-detail-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: visual.background,
                  foregroundColor: visual.foreground,
                  child: Icon(visual.icon),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.habitName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text('${_dateHeading(date)} · ${visual.label}'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _DetailRow(label: 'Schedule', value: entry.scheduleSummary),
            _DetailRow(
              label: 'Category',
              value: entry.categoryName ?? 'Uncategorized',
            ),
            if (entry.selectedOption != null)
              _DetailRow(
                label: 'Selected option',
                value: entry.selectedOption!,
              ),
            if (entry.measuredValue != null)
              _DetailRow(
                label: 'Measured value',
                value: _numberLabel(entry.measuredValue!),
              ),
            _DetailRow(label: 'Points', value: _pointsLabel(entry.points)),
            if (entry.note != null)
              _DetailRow(label: 'Note', value: entry.note!),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(label, style: Theme.of(context).textTheme.labelMedium),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            filtered
                ? Icons.filter_alt_off_outlined
                : Icons.event_note_outlined,
            size: 46,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 14),
          Text(
            filtered ? 'No matching history' : 'No habit history for this date',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 7),
          Text(
            filtered
                ? 'Try a different habit or completion filter.'
                : 'Choose another date to explore your progress.',
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
          "Couldn't load history",
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}

InputDecoration _historyInputDecoration({
  required String labelText,
  Widget? prefixIcon,
}) => InputDecoration(
  labelText: labelText,
  prefixIcon: prefixIcon,
  filled: true,
  fillColor: HomeDashboardTheme.surfaceRaised,
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: HomeDashboardTheme.outline),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: HomeDashboardTheme.outline),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: HomeDashboardTheme.mint, width: 1.5),
  ),
);

class _StatusVisual {
  const _StatusVisual({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
}

_StatusVisual _statusVisual(HistoryEntryStatus status, ColorScheme scheme) {
  return switch (status) {
    HistoryEntryStatus.completed => _StatusVisual(
      icon: Icons.check,
      label: 'Completed',
      background: scheme.primaryContainer,
      foreground: scheme.onPrimaryContainer,
    ),
    HistoryEntryStatus.missed => _StatusVisual(
      icon: Icons.close,
      label: 'Missed',
      background: scheme.errorContainer,
      foreground: scheme.onErrorContainer,
    ),
    HistoryEntryStatus.paused => _StatusVisual(
      icon: Icons.pause,
      label: 'Paused',
      background: scheme.secondaryContainer,
      foreground: scheme.onSecondaryContainer,
    ),
    HistoryEntryStatus.nonScheduled => _StatusVisual(
      icon: Icons.event_busy_outlined,
      label: 'Not scheduled',
      background: scheme.surfaceContainerHighest,
      foreground: scheme.onSurfaceVariant,
    ),
    HistoryEntryStatus.pending => _StatusVisual(
      icon: Icons.schedule,
      label: 'Pending',
      background: scheme.tertiaryContainer,
      foreground: scheme.onTertiaryContainer,
    ),
  };
}

String _completionSummary(HistoryEntry entry) {
  if (entry.selectedOption != null) return entry.selectedOption!;
  if (entry.measuredValue != null) return _numberLabel(entry.measuredValue!);
  return 'Checked in';
}

String _pointsLabel(int points) {
  if (points > 0) return '+$points points';
  return '$points points';
}

String _numberLabel(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);

String _dateHeading(DateTime date) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}
