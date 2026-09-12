import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/app/theme/app_theme.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/habits/presentation/habit_management_provider.dart';
import 'package:ruleup/features/check_ins/presentation/daily_check_in_provider.dart';
import 'package:ruleup/features/home/presentation/app_shell.dart';
import 'package:ruleup/features/home/presentation/home_dashboard_provider.dart';
import 'package:ruleup/features/history/presentation/history_provider.dart';
import 'package:ruleup/features/rewards/presentation/rewards_wallet_provider.dart';
import 'package:ruleup/features/settings/presentation/settings_provider.dart';

void main() {
  testWidgets('bottom navigation exposes all shell destinations', (
    tester,
  ) async {
    await _pumpShell(tester, dashboard: _emptyDashboard);

    expect(find.byKey(const Key('app-bottom-navigation')), findsOneWidget);
    for (final label in ['Home', 'Habits', 'Check-in', 'Rewards', 'History']) {
      expect(find.text(label), findsWidgets);
    }

    await tester.tap(find.text('Habits').last);
    await tester.pump();
    expect(find.byKey(const Key('habit-list-screen')), findsOneWidget);

    await tester.tap(find.text('Rewards').last);
    await tester.pump();
    expect(find.byKey(const Key('rewards-wallet-screen')), findsOneWidget);

    await tester.tap(find.text('History').last);
    await tester.pump();
    expect(find.byKey(const Key('history-screen')), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-screen')), findsOneWidget);
  });

  testWidgets('quick check-in CTA selects the check-in destination', (
    tester,
  ) async {
    await _pumpShell(tester, dashboard: _dashboard);
    final button = find.byKey(const Key('quick-check-in-button'));
    await tester.drag(
      find.byKey(const Key('home-dashboard-scroll')),
      const Offset(0, -320),
    );
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pump();

    expect(find.byKey(const Key('daily-check-in-screen')), findsOneWidget);
  });

  testWidgets('home dashboard renders populated motivational summary', (
    tester,
  ) async {
    await _pumpShell(tester, dashboard: _dashboard);

    expect(find.text('Good morning,'), findsOneWidget);
    expect(find.text('Tester'), findsOneWidget);
    expect(find.byKey(const Key('ruleup-brand-mark')), findsOneWidget);
    expect(find.text('Available points'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(find.text('Current streak'), findsOneWidget);
    expect(find.text('4 days'), findsOneWidget);
    expect(find.text('Ready to use on rewards'), findsOneWidget);
    expect(find.text('Keep going!'), findsOneWidget);
    expect(find.byKey(const Key('home-combined-metrics')), findsOneWidget);
    expect(find.text("Today's progress"), findsOneWidget);
    expect(find.text('2 of 3'), findsOneWidget);
    expect(find.text('67%'), findsOneWidget);
    expect(find.byKey(const Key('today-habits-section')), findsOneWidget);
    expect(find.text("Today's habits"), findsOneWidget);
    expect(find.text('Read 20 minutes'), findsOneWidget);
    expect(find.text('+10 pts'), findsOneWidget);
    expect(find.text('Completed • Today'), findsOneWidget);
    expect(find.text('Drink water'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Upcoming reminders'), findsOneWidget);
    expect(find.text('View all'), findsNWidgets(2));
    expect(find.text('Evening walk'), findsOneWidget);
  });

  testWidgets('home dashboard renders loading and error states', (
    tester,
  ) async {
    final pending = Completer<HomeDashboardData>();
    await _pumpShell(tester, dashboardFuture: pending.future, settle: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await _pumpShell(tester, dashboardError: Exception('database unavailable'));
    expect(find.text("Couldn't load your dashboard"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('home dashboard reports active sync state', (tester) async {
    await _pumpShell(tester, dashboard: _emptyDashboard, syncing: true);

    expect(find.text('Syncing'), findsOneWidget);
  });

  testWidgets('home dashboard never displays a raw sync exception', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      dashboard: _emptyDashboard,
      syncFailureMessage: 'SqliteException(787): FOREIGN KEY constraint failed',
    );

    expect(find.text("Sync couldn't finish. Tap Retry."), findsOneWidget);
    expect(find.textContaining('SqliteException'), findsNothing);
  });

  testWidgets('shell remains usable on a small phone with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpShell(tester, dashboard: _emptyDashboard, settle: false);
    expect(
      tester.takeException(),
      isNull,
      reason: 'Loading Home must fit a 320px-wide screen at 150% text scale',
    );
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason: 'Home must fit a 320px-wide screen at 150% text scale',
    );
    final labels = ['Habits', 'Check-in', 'Rewards', 'History', 'Home'];
    final destinationIndexes = [1, 2, 3, 4, 0];
    for (var index = 0; index < labels.length; index++) {
      final label = labels[index];
      await tester.tap(
        find.byType(NavigationDestination).at(destinationIndexes[index]),
      );
      await tester.pump();
      final layoutError = tester.takeException();
      expect(
        layoutError,
        isNull,
        reason: '$label must fit a 320px-wide screen at 150% text scale',
      );
    }

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-screen')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching tabs retains Home scroll position', (tester) async {
    await _pumpShell(tester, dashboard: _dashboard);
    final homeScrollable = find.descendant(
      of: find.byKey(const Key('home-dashboard-scroll')),
      matching: find.byType(Scrollable),
    );
    await tester.drag(
      find.byKey(const Key('home-dashboard-scroll')),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();
    final before = tester
        .state<ScrollableState>(homeScrollable)
        .position
        .pixels;
    expect(before, greaterThan(0));

    await tester.tap(find.byType(NavigationDestination).at(1));
    await tester.pump();
    await tester.tap(find.byType(NavigationDestination).at(0));
    await tester.pump();

    expect(
      tester.state<ScrollableState>(homeScrollable).position.pixels,
      before,
    );
  });
}

Future<void> _pumpShell(
  WidgetTester tester, {
  HomeDashboardData? dashboard,
  Future<HomeDashboardData>? dashboardFuture,
  Object? dashboardError,
  bool settle = true,
  bool syncing = false,
  String? syncFailureMessage,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        backendHealthProvider.overrideWith((ref) async {}),
        if (syncing)
          syncControllerProvider.overrideWith(_SyncingController.new),
        if (syncFailureMessage != null)
          syncControllerProvider.overrideWith(
            () => _FailedSyncController(syncFailureMessage),
          ),
        homeNowProvider.overrideWithValue(DateTime(2026, 1, 5, 9)),
        habitCatalogProvider.overrideWith(
          (ref, _) async => const HabitCatalog(habits: [], categories: []),
        ),
        dailyCheckInProvider.overrideWith(
          (ref, _) async =>
              DailyCheckInData(date: DateTime(2026, 1, 5), habits: const []),
        ),
        rewardsWalletProvider.overrideWith(
          (ref, _) async => const RewardsWalletData(
            availablePoints: 0,
            lifetimeEarned: 0,
            spentPoints: 0,
            rewards: [],
          ),
        ),
        settingsOverviewProvider.overrideWith(
          (ref, _) async => const SettingsOverview(
            pendingCount: 0,
            failedCount: 0,
            lastSuccessfulSync: null,
          ),
        ),
        historyDayProvider.overrideWith(
          (ref, query) async => HistoryDayData(
            date: query.date,
            currentStreak: 0,
            longestStreak: 0,
            habits: const [],
            entries: const [],
          ),
        ),
        homeDashboardProvider.overrideWith((ref, _) async {
          if (dashboardError != null) throw dashboardError;
          if (dashboardFuture != null) return await dashboardFuture;
          return dashboard!;
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const AppShell(userId: 'user-id', username: 'tester'),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

class _SyncingController extends SyncController {
  @override
  SyncState build() => const SyncState(status: SyncStatus.syncing);
}

class _FailedSyncController extends SyncController {
  _FailedSyncController(this.message);

  final String message;

  @override
  SyncState build() => SyncState(status: SyncStatus.failed, message: message);
}

const _emptyDashboard = HomeDashboardData(
  availablePoints: 0,
  currentStreak: 0,
  completedToday: 0,
  applicableToday: 0,
  activeHabitCount: 0,
);

final _dashboard = HomeDashboardData(
  availablePoints: 120,
  currentStreak: 4,
  streakHabitName: 'Evening walk',
  completedToday: 2,
  applicableToday: 3,
  activeHabitCount: 3,
  todayHabits: [
    TodayHabitSummary(
      habitId: 'reading-id',
      habitName: 'Read 20 minutes',
      isCompleted: true,
      awardedPoints: 10,
    ),
    TodayHabitSummary(
      habitId: 'water-id',
      habitName: 'Drink water',
      isCompleted: false,
    ),
  ],
  upcomingReminders: [
    UpcomingReminder(
      habitId: 'habit-id',
      habitName: 'Evening walk',
      scheduledAt: DateTime(2026, 1, 5, 18, 30),
    ),
  ],
);
