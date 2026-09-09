import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/home/presentation/dashboard_card.dart';
import 'package:ruleup/features/home/presentation/home_dashboard_provider.dart';
import 'package:ruleup/features/home/presentation/home_dashboard_theme.dart';

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
    return Theme(
      data: HomeDashboardTheme.create(),
      child: ColoredBox(
        color: HomeDashboardTheme.background,
        child: RefreshIndicator(
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
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _DashboardHeader(
                            greeting: _greeting(now),
                            username: _sentenceCase(username),
                            status: _connectionStatus(health, sync),
                            onRetry: sync.status == SyncStatus.failed
                                ? () => ref
                                      .read(syncControllerProvider.notifier)
                                      .retryFailed(userId)
                                : null,
                          ),
                          const SizedBox(height: 16),
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
        ),
      ),
    );
  }

  String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  String _sentenceCase(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'[_\s]+'), ' ');
    if (normalized.isEmpty) return 'Member';
    return '${normalized[0].toUpperCase()}${normalized.substring(1).toLowerCase()}';
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
        label: 'Sync issue',
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
        label: health.isLoading ? 'Checking' : 'Ready',
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(greeting, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(username, style: theme.textTheme.headlineMedium),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _StatusPill(status: status),
          ],
        ),
        if (status.detail case final detail?) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
              color: HomeDashboardTheme.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: HomeDashboardTheme.outline),
            ),
            child: Row(
              children: [
                Expanded(child: Text(detail, style: theme.textTheme.bodySmall)),
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final _ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status.tone) {
      _StatusTone.success => (const Color(0xFF173C32), HomeDashboardTheme.mint),
      _StatusTone.warning => (const Color(0xFF3E2725), const Color(0xFFFFC6BE)),
      _StatusTone.neutral => (
        HomeDashboardTheme.surfaceRaised,
        HomeDashboardTheme.mutedText,
      ),
    };
    return Semantics(
      label: 'Sync status: ${status.label}',
      child: Container(
        constraints: const BoxConstraints(maxWidth: 128),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: HomeDashboardTheme.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(status.icon, size: 14, color: foreground),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                status.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CombinedMetricsCard(data: data),
        const SizedBox(height: 10),
        _ProgressCard(data: data),
        const SizedBox(height: 10),
        FilledButton.icon(
          key: const Key('quick-check-in-button'),
          onPressed: onQuickCheckIn,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Quick check-in'),
        ),
        const SizedBox(height: 18),
        _TodayHabits(data: data),
        const SizedBox(height: 18),
        _UpcomingReminders(reminders: data.upcomingReminders, now: now),
      ],
    );
  }
}

class _CombinedMetricsCard extends StatelessWidget {
  const _CombinedMetricsCard({required this.data});
  final HomeDashboardData data;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      key: const Key('home-combined-metrics'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _Metric(
                icon: Icons.savings_outlined,
                label: 'Available points',
                value: '${data.availablePoints}',
              ),
            ),
            const VerticalDivider(width: 24),
            Expanded(
              child: _Metric(
                icon: Icons.local_fire_department_outlined,
                label: 'Current streak',
                value: '${data.currentStreak} days',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 17, color: HomeDashboardTheme.mint),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: HomeDashboardTheme.mutedText,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: theme.textTheme.headlineSmall),
        ),
      ],
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.data});
  final HomeDashboardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DashboardCard(
      key: const Key('today-progress-card'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "Today's progress",
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                data.activeHabitCount > 0
                    ? '${data.completedToday} of ${data.applicableToday}'
                    : 'No habits',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: HomeDashboardTheme.mint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: data.progress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(99),
          ),
        ],
      ),
    );
  }
}

class _TodayHabits extends StatelessWidget {
  const _TodayHabits({required this.data});
  final HomeDashboardData data;

  @override
  Widget build(BuildContext context) {
    final habits = data.todayHabits;
    return _CompactSection(
      key: const Key('today-habits-section'),
      title: "Today's habits",
      emptyIcon: Icons.event_available_outlined,
      emptyText: data.activeHabitCount == 0
          ? 'Create a habit to start building momentum.'
          : 'Nothing is scheduled for today.',
      children: [for (final habit in habits) _HabitRow(habit: habit)],
    );
  }
}

class _HabitRow extends StatelessWidget {
  const _HabitRow({required this.habit});
  final TodayHabitSummary habit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = habit.awardedPoints;
    return _CompactRow(
      icon: habit.isCompleted
          ? Icons.check_circle
          : Icons.radio_button_unchecked,
      iconColor: habit.isCompleted
          ? HomeDashboardTheme.mint
          : HomeDashboardTheme.mutedText,
      title: habit.habitName,
      trailing: habit.isCompleted
          ? points == null
                ? 'Done'
                : '${points >= 0 ? '+' : ''}$points pts'
          : 'Pending',
      trailingStyle: theme.textTheme.labelMedium?.copyWith(
        color: habit.isCompleted
            ? HomeDashboardTheme.mint
            : HomeDashboardTheme.mutedText,
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
    return _CompactSection(
      title: 'Upcoming reminders',
      emptyIcon: Icons.notifications_none_outlined,
      emptyText: 'No upcoming reminders.',
      children: [
        for (final reminder in reminders)
          _ReminderRow(reminder: reminder, now: now),
      ],
    );
  }
}

class _CompactSection extends StatelessWidget {
  const _CompactSection({
    super.key,
    required this.title,
    required this.emptyIcon,
    required this.emptyText,
    required this.children,
  });
  final String title;
  final IconData emptyIcon;
  final String emptyText;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 9),
        DashboardCard(
          padding: children.isEmpty
              ? const EdgeInsets.all(14)
              : const EdgeInsets.symmetric(vertical: 4),
          child: children.isEmpty
              ? Row(
                  children: [
                    Icon(
                      emptyIcon,
                      size: 20,
                      color: HomeDashboardTheme.mutedText,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(emptyText, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                )
              : Column(
                  children: [
                    for (var index = 0; index < children.length; index++) ...[
                      children[index],
                      if (index < children.length - 1) const Divider(),
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
    return _CompactRow(
      icon: Icons.notifications_none_outlined,
      iconColor: HomeDashboardTheme.mint,
      title: reminder.habitName,
      subtitle: _dayLabel(reminder.scheduledAt, now),
      trailing: TimeOfDay.fromDateTime(reminder.scheduledAt).format(context),
      trailingStyle: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: HomeDashboardTheme.mint),
    );
  }

  String _dayLabel(DateTime scheduledAt, DateTime now) {
    final difference = DateUtils.dateOnly(scheduledAt)
        .difference(DateUtils.dateOnly(now))
        .inDays;
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Tomorrow';
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[scheduledAt.weekday - 1];
  }
}

class _CompactRow extends StatelessWidget {
  const _CompactRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.trailing,
    this.subtitle,
    this.trailingStyle,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final String trailing;
  final TextStyle? trailingStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          Icon(icon, size: 21, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: HomeDashboardTheme.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null)
                  Text(subtitle!, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(trailing, style: trailingStyle ?? theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _DashboardLoading extends StatelessWidget {
  const _DashboardLoading();
  @override
  Widget build(BuildContext context) => const DashboardCard(
    child: SizedBox(
      height: 160,
      child: Center(child: CircularProgressIndicator()),
    ),
  );
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 28),
          const SizedBox(height: 8),
          Text(
            "Couldn't load your dashboard",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text('Your local data is safe. Try loading it again.'),
          const SizedBox(height: 10),
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
