import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/presentation/sync_status_banner.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/check_ins/presentation/check_in_form_sheet.dart';
import 'package:ruleup/features/check_ins/presentation/daily_check_in_provider.dart';
import 'package:ruleup/features/habits/domain/measurement_type.dart';
import 'package:ruleup/features/home/presentation/home_dashboard_provider.dart';

enum TodayHabitFilter { pending, all, completed }

class DailyCheckInScreen extends ConsumerStatefulWidget {
  const DailyCheckInScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<DailyCheckInScreen> createState() => _DailyCheckInScreenState();
}

class _DailyCheckInScreenState extends ConsumerState<DailyCheckInScreen> {
  var _filter = TodayHabitFilter.pending;
  final _submitting = <String>{};

  @override
  Widget build(BuildContext context) {
    final day = ref.watch(dailyCheckInProvider(widget.userId));
    final health = ref.watch(backendHealthProvider);
    final sync = ref.watch(syncControllerProvider);
    return Scaffold(
      key: const Key('daily-check-in-screen'),
      backgroundColor: Colors.transparent,
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await ref
                .read(syncControllerProvider.notifier)
                .synchronize(widget.userId);
            ref.invalidate(dailyCheckInProvider(widget.userId));
          },
          child: CustomScrollView(
            key: const Key('daily-check-in-scroll'),
            slivers: [
              SliverToBoxAdapter(child: _header(day.asData?.value)),
              if (health.hasError ||
                  sync.status == SyncStatus.syncing ||
                  sync.status == SyncStatus.failed)
                SliverToBoxAdapter(
                  child: SyncStatusBanner(
                    offline: health.hasError,
                    sync: sync,
                    offlineMessage: 'Offline — check-ins save locally and sync when connection returns.',
                    syncingMessage: 'Syncing today’s progress…',
                    failedMessage: 'Some check-ins are waiting to sync.',
                    onRetry: () => ref
                        .read(syncControllerProvider.notifier)
                        .retryFailed(widget.userId),
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  ),
                ),
              switch (day) {
                AsyncData(:final value) => _habitSliver(value),
                AsyncError() => SliverFillRemaining(
                  hasScrollBody: false,
                  child: _ErrorState(
                    onRetry: () =>
                        ref.invalidate(dailyCheckInProvider(widget.userId)),
                  ),
                ),
                _ => const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                ),
              },
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(DailyCheckInData? data) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today’s check-in',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            data == null
                ? 'Loading your plan…'
                : '${data.completedCount} of ${data.habits.length} complete',
          ),
          if (data != null && data.habits.isNotEmpty) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: data.completedCount / data.habits.length,
              borderRadius: BorderRadius.circular(8),
              minHeight: 7,
            ),
          ],
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<TodayHabitFilter>(
              segments: const [
                ButtonSegment(
                  value: TodayHabitFilter.pending,
                  label: Text('Pending'),
                ),
                ButtonSegment(value: TodayHabitFilter.all, label: Text('All')),
                ButtonSegment(
                  value: TodayHabitFilter.completed,
                  label: Text('Completed'),
                ),
              ],
              selected: {_filter},
              onSelectionChanged: (value) =>
                  setState(() => _filter = value.first),
            ),
          ),
        ],
      ),
    );
  }

  Widget _habitSliver(DailyCheckInData data) {
    final visible = data.habits
        .where((habit) {
          return switch (_filter) {
            TodayHabitFilter.pending => !habit.isCompleted,
            TodayHabitFilter.all => true,
            TodayHabitFilter.completed => habit.isCompleted,
          };
        })
        .toList(growable: false);
    if (visible.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyState(filter: _filter, hasHabits: data.habits.isNotEmpty),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      sliver: SliverList.separated(
        itemCount: visible.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final habit = visible[index];
          return _CheckInCard(
            habit: habit,
            submitting: _submitting.contains(habit.id),
            onOpen: () => _openForm(data, habit),
            onQuickComplete:
                habit.measurementType == MeasurementType.yesNo &&
                    habit.options.isEmpty &&
                    !habit.isCompleted
                ? () => _quickComplete(data, habit)
                : null,
          );
        },
      ),
    );
  }

  Future<void> _quickComplete(
    DailyCheckInData data,
    DailyHabitEntry habit,
  ) async {
    setState(() => _submitting.add(habit.id));
    try {
      final result = await ref.read(checkInSubmitActionProvider)(
        widget.userId,
        CheckInSubmission(habitId: habit.id, habitDate: data.date),
      );
      if (mounted) _handleSuccess(result);
    } on Object catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _submitting.remove(habit.id));
    }
  }

  Future<void> _openForm(DailyCheckInData data, DailyHabitEntry habit) async {
    if (habit.checkIn?.locked == true) return;
    final result = await showModalBottomSheet<CheckInSubmitResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      builder: (_) => CheckInFormSheet(
        habit: habit,
        habitDate: data.date,
        onSubmit: (submission) =>
            ref.read(checkInSubmitActionProvider)(widget.userId, submission),
      ),
    );
    if (result != null && mounted) _handleSuccess(result);
  }

  void _handleSuccess(CheckInSubmitResult result) {
    ref.invalidate(dailyCheckInProvider(widget.userId));
    ref.invalidate(homeDashboardProvider(widget.userId));
    final message = result.updated
        ? 'Check-in updated · ${_pointsLabel(result.points)} total'
        : result.points > 0
        ? '+${result.points} points earned'
        : result.points < 0
        ? '${result.points.abs()} points deducted'
        : 'Check-in complete';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('check-in-points-feedback'),
        content: Text(message),
      ),
    );
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(_friendlyError(error))));
  }
}

class _CheckInCard extends StatelessWidget {
  const _CheckInCard({
    required this.habit,
    required this.submitting,
    required this.onOpen,
    this.onQuickComplete,
  });

  final DailyHabitEntry habit;
  final bool submitting;
  final VoidCallback onOpen;
  final VoidCallback? onQuickComplete;

  @override
  Widget build(BuildContext context) {
    final checkIn = habit.checkIn;
    final locked = checkIn?.locked == true;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        key: Key('check-in-card-${habit.id}'),
        onTap: locked ? null : onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: habit.isCompleted
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHighest,
                    foregroundColor: habit.isCompleted
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                    child: Icon(
                      habit.isCompleted
                          ? Icons.check
                          : _measurementIcon(habit.measurementType),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          habit.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          habit.categoryName ?? 'Uncategorized',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (habit.currentStreak > 0)
                    _ContextChip(
                      icon: Icons.local_fire_department_outlined,
                      label: '${habit.currentStreak} day streak',
                    ),
                  _ContextChip(
                    icon: Icons.calendar_today_outlined,
                    label: habit.scheduleSummary,
                  ),
                  if (habit.reminderTime != null)
                    _ContextChip(
                      icon: Icons.notifications_active_outlined,
                      label: habit.reminderTime!,
                    ),
                  _ContextChip(
                    icon: _measurementIcon(habit.measurementType),
                    label: _measurementLabel(habit.measurementType),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (checkIn == null)
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    key: Key('check-in-action-${habit.id}'),
                    onPressed: submitting ? null : onQuickComplete ?? onOpen,
                    icon: submitting
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(
                      onQuickComplete == null ? 'Check in' : 'Complete',
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        checkIn.awardedPoints == 0
                            ? 'Completed today'
                            : '${_pointsLabel(checkIn.awardedPoints)} awarded',
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(color: scheme.primary),
                      ),
                    ),
                    if (locked)
                      Tooltip(
                        message:
                            'Editing closed ${_dateTimeLabel(checkIn.editableUntil)}',
                        child: const Chip(
                          avatar: Icon(Icons.lock_outline, size: 16),
                          label: Text('Locked'),
                        ),
                      )
                    else
                      TextButton.icon(
                        key: Key('edit-check-in-${habit.id}'),
                        onPressed: onOpen,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit'),
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

class _ContextChip extends StatelessWidget {
  const _ContextChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter, required this.hasHabits});

  final TodayHabitFilter filter;
  final bool hasHabits;

  @override
  Widget build(BuildContext context) {
    final title = !hasHabits
        ? 'Nothing scheduled today'
        : filter == TodayHabitFilter.pending
        ? 'You’re all caught up'
        : filter == TodayHabitFilter.completed
        ? 'No check-ins yet'
        : 'Nothing scheduled today';
    final message = !hasHabits
        ? 'Paused and non-scheduled habits stay out of your way.'
        : filter == TodayHabitFilter.pending
        ? 'Every applicable habit is complete. Nice work.'
        : 'Completed habits will appear here.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasHabits ? Icons.done_all : Icons.event_available_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
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
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 44),
          const SizedBox(height: 12),
          Text(
            "Couldn't load today’s habits",
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

String _pointsLabel(int points) =>
    points > 0 ? '+$points points' : '$points points';

String _dateTimeLabel(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')} '
    '${date.hour.toString().padLeft(2, '0')}:'
    '${date.minute.toString().padLeft(2, '0')}';

String _friendlyError(Object error) {
  final message = error
      .toString()
      .replaceFirst('ArgumentError: ', '')
      .replaceFirst('CheckInLockedException', 'This check-in is now locked');
  return message.length <= 180 ? message : '${message.substring(0, 177)}…';
}
