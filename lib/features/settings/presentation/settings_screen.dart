import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/settings/presentation/settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({
    super.key,
    required this.userId,
    required this.username,
  });

  final String userId;
  final String username;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  var _permission = NotificationPermissionState.unknown;
  var _checkingPermission = false;
  var _refreshingReminders = false;
  String? _reminderMessage;

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(settingsOverviewProvider(widget.userId));
    final sync = ref.watch(syncControllerProvider);
    final health = ref.watch(backendHealthProvider);
    return Scaffold(
      key: const Key('settings-screen'),
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _syncNow,
          child: ListView(
            key: const Key('settings-scroll'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              if (health.hasError)
                _OfflineNotice(
                  onRetry: () => ref.invalidate(backendHealthProvider),
                )
              else if (health.isLoading)
                const LinearProgressIndicator(
                  key: Key('settings-health-loading'),
                ),
              _Section(
                title: 'Account',
                icon: Icons.person_outline,
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(widget.username),
                      subtitle: const Text('Signed in username'),
                    ),
                    const Divider(),
                    ListTile(
                      key: const Key('settings-logout'),
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.logout,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: Text(
                        'Log out',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      subtitle: const Text('End this session on this device'),
                      onTap: _confirmLogout,
                    ),
                  ],
                ),
              ),
              _Section(
                title: 'Sync',
                icon: Icons.sync,
                child: _SyncSection(
                  overview: overview,
                  sync: sync,
                  offline: health.hasError,
                  onRetryOverview: () =>
                      ref.invalidate(settingsOverviewProvider(widget.userId)),
                  onSync: _syncNow,
                ),
              ),
              _Section(
                title: 'Reminders',
                icon: Icons.notifications_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_permissionIcon(_permission)),
                      title: const Text('Notification permission'),
                      subtitle: Text(_permissionLabel(_permission)),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          key: const Key('check-notification-permission'),
                          onPressed: _checkingPermission
                              ? null
                              : _checkPermission,
                          icon: _checkingPermission
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.shield_outlined),
                          label: const Text('Check permission'),
                        ),
                        FilledButton.tonalIcon(
                          key: const Key('refresh-reminders'),
                          onPressed: _refreshingReminders
                              ? null
                              : _refreshReminders,
                          icon: _refreshingReminders
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh),
                          label: const Text('Reschedule'),
                        ),
                      ],
                    ),
                    if (_reminderMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _reminderMessage!,
                        key: const Key('reminder-status-message'),
                      ),
                    ],
                  ],
                ),
              ),
              const _Section(
                title: 'App',
                icon: Icons.info_outline,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.track_changes),
                  title: Text('RuleUp'),
                  subtitle: Text('Version 1.0.0 (1)'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _syncNow() async {
    final overview = ref.read(settingsOverviewProvider(widget.userId)).value;
    final sync = ref.read(syncControllerProvider);
    final retry =
        sync.status == SyncStatus.failed ||
        (overview != null && overview.failedCount > 0);
    await ref.read(settingsSyncActionProvider)(widget.userId, retry: retry);
    ref.invalidate(settingsOverviewProvider(widget.userId));
  }

  Future<void> _checkPermission() async {
    setState(() => _checkingPermission = true);
    final result = await ref.read(notificationPermissionActionProvider)();
    if (!mounted) return;
    setState(() {
      _permission = result;
      _checkingPermission = false;
    });
  }

  Future<void> _refreshReminders() async {
    setState(() {
      _refreshingReminders = true;
      _reminderMessage = null;
    });
    try {
      final result = await ref.read(reminderRefreshActionProvider)(
        widget.userId,
      );
      if (!mounted) return;
      setState(() {
        _refreshingReminders = false;
        _reminderMessage = _reminderResultLabel(result);
        if (result.permissionDenied) {
          _permission = NotificationPermissionState.denied;
        }
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _refreshingReminders = false;
        _reminderMessage =
            'Reminders could not be refreshed. Your habit data is unaffected.';
      });
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'Your local data will stay on this device and sync again after login.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-logout'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(settingsLogoutActionProvider)();
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

class _SyncSection extends StatelessWidget {
  const _SyncSection({
    required this.overview,
    required this.sync,
    required this.offline,
    required this.onRetryOverview,
    required this.onSync,
  });

  final AsyncValue<SettingsOverview> overview;
  final SyncState sync;
  final bool offline;
  final VoidCallback onRetryOverview;
  final Future<void> Function() onSync;

  @override
  Widget build(BuildContext context) {
    return switch (overview) {
      AsyncData(:final value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              _StatusChip(sync: sync, offline: offline),
              Text(_lastSyncLabel(value.lastSuccessfulSync)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _CountTile(
                  key: const Key('pending-sync-count'),
                  label: 'Pending',
                  value: value.pendingCount,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CountTile(
                  key: const Key('failed-sync-count'),
                  label: 'Failed',
                  value: value.failedCount,
                ),
              ),
            ],
          ),
          if (sync.message != null || value.syncErrors.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Needs attention',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            if (sync.message != null) Text(sync.message!),
            ...value.syncErrors.map(
              (message) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• $message'),
              ),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const Key('manual-sync'),
            onPressed: sync.status == SyncStatus.syncing || offline
                ? null
                : onSync,
            icon: sync.status == SyncStatus.syncing
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(value.failedCount > 0 ? Icons.refresh : Icons.sync),
            label: Text(value.failedCount > 0 ? 'Retry failed' : 'Sync now'),
          ),
        ],
      ),
      AsyncError() => _InlineError(onRetry: onRetryOverview),
      _ => const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(key: Key('settings-sync-loading')),
        ),
      ),
    };
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    ),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.sync, required this.offline});

  final SyncState sync;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final label = offline ? 'Offline' : _syncStatusLabel(sync.status);
    final icon = offline
        ? Icons.cloud_off_outlined
        : _syncStatusIcon(sync.status);
    return Chip(
      key: const Key('settings-sync-status'),
      avatar: Icon(icon, size: 17),
      label: Text(label),
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({super.key, required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', style: Theme.of(context).textTheme.headlineSmall),
          Text(label),
        ],
      ),
    ),
  );
}

class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      key: const Key('settings-offline'),
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_outlined),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Offline — local changes are safe and will sync later.',
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const Text("Couldn't load sync details."),
      const SizedBox(height: 8),
      OutlinedButton(
        key: const Key('retry-settings-overview'),
        onPressed: onRetry,
        child: const Text('Try again'),
      ),
    ],
  );
}

String _syncStatusLabel(SyncStatus status) => switch (status) {
  SyncStatus.idle => 'Ready',
  SyncStatus.syncing => 'Syncing',
  SyncStatus.succeeded => 'Up to date',
  SyncStatus.failed => 'Needs attention',
};

IconData _syncStatusIcon(SyncStatus status) => switch (status) {
  SyncStatus.idle => Icons.cloud_done_outlined,
  SyncStatus.syncing => Icons.sync,
  SyncStatus.succeeded => Icons.cloud_done_outlined,
  SyncStatus.failed => Icons.sync_problem_outlined,
};

IconData _permissionIcon(NotificationPermissionState state) => switch (state) {
  NotificationPermissionState.granted => Icons.notifications_active_outlined,
  NotificationPermissionState.denied => Icons.notifications_off_outlined,
  NotificationPermissionState.unavailable => Icons.phone_android_outlined,
  NotificationPermissionState.error => Icons.error_outline,
  NotificationPermissionState.unknown => Icons.help_outline,
};

String _permissionLabel(NotificationPermissionState state) => switch (state) {
  NotificationPermissionState.granted => 'Allowed',
  NotificationPermissionState.denied => 'Not allowed',
  NotificationPermissionState.unavailable => 'Android only',
  NotificationPermissionState.error => 'Could not check permission',
  NotificationPermissionState.unknown => 'Not checked',
};

String _reminderResultLabel(ReminderRefreshResult result) {
  if (result.permissionDenied) {
    return 'Permission is not allowed. No reminders were scheduled.';
  }
  if (result.failed) {
    return 'Some reminders could not be refreshed. Habit data is unaffected.';
  }
  if (result.reminderCount == 0) return 'No reminders to reschedule.';
  return '${result.scheduledCount} upcoming reminders scheduled.';
}

String _lastSyncLabel(DateTime? value) {
  if (value == null) return 'Not synced yet';
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return 'Last sync ${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
