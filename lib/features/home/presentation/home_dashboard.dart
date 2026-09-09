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
    required this.onOpenSettings,
  });

  final String userId;
  final String username;
  final VoidCallback onQuickCheckIn;
  final VoidCallback onOpenSettings;

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
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: () async {
              await ref
                  .read(syncControllerProvider.notifier)
                  .synchronize(userId);
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
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _DashboardHeader(
                              greeting: _greeting(now),
                              username: _sentenceCase(username),
                              status: _connectionStatus(health, sync),
                              onOpenSettings: onOpenSettings,
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
                                onRetry: () => ref.invalidate(
                                  homeDashboardProvider(userId),
                                ),
                              ),
                              data: (data) => _DashboardContent(
                                data: data,
                                now: now,
                                onQuickCheckIn: onQuickCheckIn,
                                onOpenSettings: onOpenSettings,
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
    required this.onOpenSettings,
    this.onRetry,
  });

  final String greeting;
  final String username;
  final _ConnectionStatus status;
  final VoidCallback onOpenSettings;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _RuleUpMark(),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Rule',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: HomeDashboardTheme.text,
                      ),
                    ),
                    TextSpan(
                      text: 'Up',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: HomeDashboardTheme.mint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              key: const Key('open-settings'),
              tooltip: 'Settings',
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_outlined, size: 29),
            ),
          ],
        ),
        const SizedBox(height: 26),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$greeting,', style: theme.textTheme.bodyLarge),
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

class _RuleUpMark extends StatelessWidget {
  const _RuleUpMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('ruleup-brand-mark'),
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: HomeDashboardTheme.mint,
        borderRadius: BorderRadius.circular(13),
      ),
      child: const Icon(Icons.eco_rounded, size: 30, color: Color(0xFF073328)),
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
    required this.onOpenSettings,
  });
  final HomeDashboardData data;
  final DateTime now;
  final VoidCallback onQuickCheckIn;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CombinedMetricsCard(data: data),
        const SizedBox(height: 16),
        _ProgressCard(data: data),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('quick-check-in-button'),
          onPressed: onQuickCheckIn,
          child: const Row(
            children: [
              _CheckInActionIcon(),
              SizedBox(width: 14),
              Expanded(child: Text('Quick check-in')),
              Icon(Icons.arrow_forward_rounded, size: 25),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _TodayHabits(data: data, onViewAll: onQuickCheckIn),
        const SizedBox(height: 16),
        _UpcomingReminders(
          reminders: data.upcomingReminders,
          now: now,
          onViewAll: onOpenSettings,
        ),
      ],
    );
  }
}

class _CheckInActionIcon extends StatelessWidget {
  const _CheckInActionIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: const BoxDecoration(
        color: HomeDashboardTheme.background,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.add_rounded,
        size: 28,
        color: HomeDashboardTheme.mint,
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _Metric(
                icon: Icons.toll_rounded,
                label: 'Available points',
                value: '${data.availablePoints}',
                supporting: 'Ready to use on rewards',
                iconColor: HomeDashboardTheme.mint,
                iconBackground: const Color(0xFF12392F),
              ),
            ),
            const VerticalDivider(width: 28),
            Expanded(
              child: _Metric(
                icon: Icons.local_fire_department_outlined,
                label: 'Current streak',
                value: '${data.currentStreak} days',
                supporting: 'Keep going!',
                iconColor: const Color(0xFFFFB83E),
                iconBackground: const Color(0xFF3A3020),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    required this.supporting,
    required this.iconColor,
    required this.iconBackground,
  });
  final IconData icon;
  final String label;
  final String value;
  final String supporting;
  final Color iconColor;
  final Color iconBackground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 24, color: iconColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: HomeDashboardTheme.mutedText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, style: theme.textTheme.headlineSmall),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 21,
              color: HomeDashboardTheme.mutedText,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 52),
          child: Text(
            supporting,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
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
    final percent = (data.progress * 100).round();
    final supporting = data.activeHabitCount == 0
        ? 'Create your first habit to begin.'
        : data.applicableToday == 0
        ? 'Nothing is scheduled for today.'
        : data.completedToday == data.applicableToday
        ? "Great! You've completed all your habits for today."
        : 'Keep going—each check-in moves the day forward.';
    return DashboardCard(
      key: const Key('today-progress-card'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
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
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label:
                      '${data.completedToday} of ${data.applicableToday} habits complete',
                  child: LinearProgressIndicator(
                    value: data.progress,
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$percent%',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: HomeDashboardTheme.mint,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            supporting,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _TodayHabits extends StatelessWidget {
  const _TodayHabits({required this.data, required this.onViewAll});
  final HomeDashboardData data;
  final VoidCallback onViewAll;

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
      onViewAll: onViewAll,
      children: [for (final habit in habits) _HabitRow(habit: habit)],
    );
  }
}

class _HabitRow extends StatelessWidget {
  const _HabitRow({required this.habit});
  final TodayHabitSummary habit;

  @override
  Widget build(BuildContext context) {
    final points = habit.awardedPoints;
    return _CompactRow(
      icon: Icons.track_changes_rounded,
      iconColor: HomeDashboardTheme.mint,
      iconBackground: const Color(0xFF12392F),
      title: habit.habitName,
      subtitle: habit.isCompleted ? 'Completed • Today' : 'Today • Pending',
      trailing: habit.isCompleted
          ? points == null
                ? 'Done'
                : '${points >= 0 ? '+' : ''}$points pts'
          : 'Pending',
      completed: habit.isCompleted,
    );
  }
}

class _UpcomingReminders extends StatelessWidget {
  const _UpcomingReminders({
    required this.reminders,
    required this.now,
    required this.onViewAll,
  });
  final List<UpcomingReminder> reminders;
  final DateTime now;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Upcoming reminders', onViewAll: onViewAll),
        const SizedBox(height: 8),
        DashboardCard(
          padding: reminders.isEmpty
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 20)
              : const EdgeInsets.symmetric(vertical: 4),
          child: reminders.isEmpty
              ? Column(
                  children: [
                    const Icon(
                      Icons.notifications_none_rounded,
                      size: 34,
                      color: HomeDashboardTheme.mutedText,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No upcoming reminders',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      "You're all caught up!",
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                )
              : Column(
                  children: [
                    for (var index = 0; index < reminders.length; index++) ...[
                      _ReminderRow(reminder: reminders[index], now: now),
                      if (index < reminders.length - 1) const Divider(),
                    ],
                  ],
                ),
        ),
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
    required this.onViewAll,
  });
  final String title;
  final IconData emptyIcon;
  final String emptyText;
  final List<Widget> children;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: title, onViewAll: onViewAll),
        const SizedBox(height: 8),
        DashboardCard(
          padding: children.isEmpty
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 13)
              : const EdgeInsets.symmetric(vertical: 4),
          child: children.isEmpty
              ? Row(
                  children: [
                    Icon(
                      emptyIcon,
                      size: 22,
                      color: HomeDashboardTheme.mutedText,
                    ),
                    const SizedBox(width: 12),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.onViewAll});

  final String title;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        TextButton.icon(
          onPressed: onViewAll,
          label: const Text('View all'),
          iconAlignment: IconAlignment.end,
          icon: const Icon(Icons.chevron_right_rounded, size: 20),
          style: TextButton.styleFrom(
            foregroundColor: HomeDashboardTheme.mint,
            minimumSize: const Size(48, 40),
            padding: const EdgeInsets.only(left: 10),
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
      icon: Icons.notifications_none_rounded,
      iconColor: HomeDashboardTheme.mint,
      iconBackground: const Color(0xFF12392F),
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
    this.iconBackground,
    required this.title,
    required this.trailing,
    this.subtitle,
    this.trailingStyle,
    this.completed = false,
  });
  final IconData icon;
  final Color iconColor;
  final Color? iconBackground;
  final String title;
  final String? subtitle;
  final String trailing;
  final TextStyle? trailingStyle;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 24, color: iconColor),
          ),
          const SizedBox(width: 12),
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
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 58),
            child: Text(
              trailing,
              textAlign: TextAlign.end,
              style: trailingStyle ?? theme.textTheme.labelMedium,
            ),
          ),
          if (completed) ...[
            const SizedBox(width: 9),
            const Icon(
              Icons.check_circle_rounded,
              size: 28,
              color: HomeDashboardTheme.mint,
            ),
          ],
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
