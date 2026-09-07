import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/settings/presentation/settings_provider.dart';
import 'package:ruleup/features/settings/presentation/settings_screen.dart';

void main() {
  testWidgets('shows account and confirms logout', (tester) async {
    var logoutCalls = 0;
    await _pumpSettings(tester, logout: () async => logoutCalls++);

    expect(find.text('tester'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-logout')));
    await tester.pumpAndSettle();
    expect(find.text('Log out?'), findsOneWidget);
    expect(logoutCalls, 0);

    await tester.tap(find.byKey(const Key('confirm-logout')));
    await tester.pumpAndSettle();
    expect(logoutCalls, 1);
  });

  testWidgets('shows sync status, counts, errors, and retries failures', (
    tester,
  ) async {
    bool? retried;
    await _pumpSettings(
      tester,
      overview: SettingsOverview(
        pendingCount: 4,
        failedCount: 2,
        lastSuccessfulSync: DateTime.utc(2026, 1, 5, 8, 30),
        syncErrors: const ['Server rejected an outdated category update.'],
      ),
      syncAction: (_, {required retry}) async => retried = retry,
      failedSync: true,
    );

    expect(find.text('Needs attention'), findsWidgets);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(
      find.text('• Server rejected an outdated category update.'),
      findsOneWidget,
    );
    expect(find.text('Retry failed'), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('settings-scroll')),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manual-sync')));
    await tester.pumpAndSettle();
    expect(retried, isTrue);
  });

  testWidgets('checks notification permission and reschedules reminders', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      permissionAction: () async => NotificationPermissionState.granted,
      reminderAction: (_) async => const ReminderRefreshResult(
        reminderCount: 2,
        scheduledCount: 8,
        permissionDenied: false,
        failed: false,
      ),
    );

    await tester.dragUntilVisible(
      find.byKey(const Key('check-notification-permission')),
      find.byKey(const Key('settings-scroll')),
      const Offset(0, -250),
    );
    await tester.tap(find.byKey(const Key('check-notification-permission')));
    await tester.pumpAndSettle();
    expect(find.text('Allowed'), findsOneWidget);

    await tester.tap(find.byKey(const Key('refresh-reminders')));
    await tester.pumpAndSettle();
    expect(find.text('8 upcoming reminders scheduled.'), findsOneWidget);
  });

  testWidgets('shows sync loading, error retry, and offline states', (
    tester,
  ) async {
    final pending = Completer<SettingsOverview>();
    await _pumpSettings(tester, overviewFuture: pending.future, settle: false);
    expect(find.byKey(const Key('settings-sync-loading')), findsOneWidget);

    await _pumpSettings(tester, overviewError: Exception('database failed'));
    expect(find.text("Couldn't load sync details."), findsOneWidget);
    expect(find.byKey(const Key('retry-settings-overview')), findsOneWidget);

    await _pumpSettings(tester, offline: true);
    expect(find.byKey(const Key('settings-offline')), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('manual-sync')))
          .onPressed,
      isNull,
    );
  });
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  SettingsOverview overview = const SettingsOverview(
    pendingCount: 0,
    failedCount: 0,
    lastSuccessfulSync: null,
  ),
  Future<SettingsOverview>? overviewFuture,
  Object? overviewError,
  Future<void> Function()? logout,
  SettingsSyncAction? syncAction,
  NotificationPermissionAction? permissionAction,
  ReminderRefreshAction? reminderAction,
  bool failedSync = false,
  bool offline = false,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        backendHealthProvider.overrideWith((ref) async {
          if (offline) throw Exception('offline');
        }),
        settingsOverviewProvider.overrideWith((ref, _) async {
          if (overviewError != null) throw overviewError;
          if (overviewFuture != null) return overviewFuture;
          return overview;
        }),
        if (failedSync)
          syncControllerProvider.overrideWith(_FailedSyncController.new),
        settingsLogoutActionProvider.overrideWithValue(logout ?? () async {}),
        settingsSyncActionProvider.overrideWithValue(
          syncAction ?? (_, {required retry}) async {},
        ),
        notificationPermissionActionProvider.overrideWithValue(
          permissionAction ?? () async => NotificationPermissionState.unknown,
        ),
        reminderRefreshActionProvider.overrideWithValue(
          reminderAction ??
              (_) async => const ReminderRefreshResult(
                reminderCount: 0,
                scheduledCount: 0,
                permissionDenied: false,
                failed: false,
              ),
        ),
      ],
      child: const MaterialApp(
        home: SettingsScreen(userId: 'user-id', username: 'tester'),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

class _FailedSyncController extends SyncController {
  @override
  SyncState build() => const SyncState(
    status: SyncStatus.failed,
    message: 'Sync paused after a network failure.',
  );
}
