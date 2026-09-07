import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/home/presentation/dashboard_card.dart';
import 'package:ruleup/features/home/presentation/home_dashboard_provider.dart';

class HomeDashboard extends ConsumerWidget {
  const HomeDashboard({
    super.key,
    required this.userId,
    required this.username,
    required this.onQuickCheckIn,
  });

  final String userId;
  final String username;
  final VoidCallback onQuickCheckIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(homeDashboardProvider(userId));
    final health = ref.watch(backendHealthProvider);
    final sync = ref.watch(syncControllerProvider);
    final now = ref.watch(homeNowProvider);

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(syncControllerProvider.notifier).synchronize(userId);
        ref.invalidate(homeDashboardProvider(userId));
        await ref.read(homeDashboardProvider(userId).future);
      },
      child: CustomScrollView(
        key: const Key('home-dashboard-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DashboardHeader(
                        greeting: _greeting(now),
                        username: username,
                        status: _connectionStatus(health, sync),
                        onRetry: sync.status == SyncStatus.failed
                            ? () => ref
                                  .read(syncControllerProvider.notifier)
                                  .retryFailed(userId)
                            : null,
                      ),
                      const SizedBox(height: 24),
                      dashboard.when(
                        loading: () => const _DashboardLoading(),
                        error: (error, _) => _DashboardError(
                          onRetry: () =>
                              ref.invalidate(homeDashboardProvider(userId)),
                        ),
                        data: (data) => _DashboardContent(
                          data: data,
                          now: now,
                          onQuickCheckIn: onQuickCheckIn,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  _ConnectionStatus _connectionStatus(AsyncValue<void> health, SyncState sync) {
    if (health.hasError) {
      return const _ConnectionStatus(
        label: 'Offline',
        icon: Icons.cloud_off_outlined,
        tone: _StatusTone.warning,
        detail: 'Changes stay on this device and will sync when reconnected.',
      );
    }
    return switch (sync.status) {
      SyncStatus.syncing => const _ConnectionStatus(
        label: 'Syncing',
        icon: Icons.sync,
        tone: _StatusTone.neutral,
      ),
      SyncStatus.failed => _ConnectionStatus(
        label: 'Sync needs attention',
        icon: Icons.sync_problem_outlined,
        tone: _StatusTone.warning,
        detail: sync.message,
      ),
      SyncStatus.succeeded => const _ConnectionStatus(
        label: 'Up to date',
        icon: Icons.cloud_done_outlined,
        tone: _StatusTone.success,
      ),
      SyncStatus.idle => _ConnectionStatus(
        label: health.isLoading ? 'Checking connection' : 'Ready',
        icon: health.isLoading
            ? Icons.cloud_sync_outlined
            : Icons.cloud_outlined,
        tone: _StatusTone.neutral,
      ),
    };
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.greeting,
    required this.username,
    required this.status,
    this.onRetry,
  });

  final String greeting;
  final String username;
  final _ConnectionStatus status;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(greeting, style: theme.textTheme.bodyLarge),
                Text(
                  username,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            _StatusChip(status: status),
          ],
        ),
        if (status.detail case final detail?) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(child: Text(detail)),
                if (onRetry != null)
                  TextButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final _ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (background, foreground) = switch (status.tone) {
      _StatusTone.success => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      _StatusTone.warning => (colors.errorContainer, colors.onErrorContainer),
      _StatusTone.neutral => (
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 18, color: foreground),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              status.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.data,
    required this.now,
    required this.onQuickCheckIn,
  });

  final HomeDashboardData data;
  final DateTime now;
  final VoidCallback onQuickCheckIn;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 680;
        final points = _MetricCard(
          icon: Icons.savings_outlined,
          label: 'Available points',
          value: '${data.availablePoints}',
          supporting: 'Ready to use on your rewards',
        );
        final streak = _MetricCard(
          icon: Icons.local_fire_department_outlined,
          label: 'Current streak',
          value: '${data.currentStreak} days',
          supporting: data.streakHabitName ?? 'Start with one steady day',
        );
        final metrics = wide
            ? Row(
                children: [
                  Expanded(child: points),
                  const SizedBox(width: 16),
                  Expanded(child: streak),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [points, const SizedBox(height: 16), streak],
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            metrics,
            const SizedBox(height: 16),
            _ProgressCard(data: data),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('quick-check-in-button'),
              onPressed: onQuickCheckIn,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Quick check-in'),
            ),
            const SizedBox(height: 24),
            _UpcomingReminders(reminders: data.upcomingReminders, now: now),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.supporting,
  });

  final IconData icon;
  final String label;
  final String value;
  final String supporting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(label, style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(supporting, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.data});

  final HomeDashboardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (data.activeHabitCount == 0) {
      return DashboardCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.spa_outlined, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text('No habits yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text(
              'Your daily progress will appear here once you add your first habit.',
            ),
          ],
        ),
      );
    }
    final complete =
        data.applicableToday > 0 && data.completedToday == data.applicableToday;
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "Today's habit progress",
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text('${data.completedToday} of ${data.applicableToday}'),
            ],
          ),
          const SizedBox(height: 14),
          LinearProgressIndicator(
            value: data.progress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(99),
          ),
          const SizedBox(height: 10),
          Text(
            data.applicableToday == 0
                ? 'Nothing is scheduled for today. Take the breathing room.'
                : complete
                ? 'Today is complete. Nice, steady work.'
                : 'A small check-in keeps the day moving.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _UpcomingReminders extends StatelessWidget {
  const _UpcomingReminders({required this.reminders, required this.now});

  final List<UpcomingReminder> reminders;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Upcoming reminders',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        DashboardCard(
          padding: reminders.isEmpty
              ? const EdgeInsets.all(20)
              : const EdgeInsets.symmetric(vertical: 6),
          child: reminders.isEmpty
              ? const Row(
                  children: [
                    Icon(Icons.notifications_none_outlined),
                    SizedBox(width: 12),
                    Expanded(child: Text('No upcoming reminders.')),
                  ],
                )
              : Column(
                  children: [
                    for (var index = 0; index < reminders.length; index++) ...[
                      _ReminderRow(reminder: reminders[index], now: now),
                      if (index < reminders.length - 1)
                        const Divider(height: 1),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({required this.reminder, required this.now});

  final UpcomingReminder reminder;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.notifications_active_outlined),
      title: Text(reminder.habitName),
      subtitle: Text(_dayLabel(reminder.scheduledAt, now)),
      trailing: Text(
        TimeOfDay.fromDateTime(reminder.scheduledAt).format(context),
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }

  String _dayLabel(DateTime scheduledAt, DateTime now) {
    final current = DateUtils.dateOnly(now);
    final scheduled = DateUtils.dateOnly(scheduledAt);
    final difference = scheduled.difference(current).inDays;
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Tomorrow';
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[scheduledAt.weekday - 1];
  }
}

class _DashboardLoading extends StatelessWidget {
  const _DashboardLoading();

  @override
  Widget build(BuildContext context) {
    return const DashboardCard(
      child: SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 32),
          const SizedBox(height: 12),
          Text(
            "Couldn't load your dashboard",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text('Your local data is safe. Try loading it again.'),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

enum _StatusTone { success, warning, neutral }

class _ConnectionStatus {
  const _ConnectionStatus({
    required this.label,
    required this.icon,
    required this.tone,
    this.detail,
  });

  final String label;
  final IconData icon;
  final _StatusTone tone;
  final String? detail;
}
