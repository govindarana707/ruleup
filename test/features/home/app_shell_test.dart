import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

    expect(find.text('Good morning'), findsOneWidget);
    expect(find.text('tester'), findsOneWidget);
    expect(find.text('Available points'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(find.text('Current streak'), findsOneWidget);
    expect(find.text('4 days'), findsOneWidget);
    expect(find.text("Today's habit progress"), findsOneWidget);
    expect(find.text('2 of 3'), findsOneWidget);
    expect(find.text('Upcoming reminders'), findsOneWidget);
    expect(find.text('Evening walk'), findsNWidgets(2));
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
}

Future<void> _pumpShell(
  WidgetTester tester, {
  HomeDashboardData? dashboard,
  Future<HomeDashboardData>? dashboardFuture,
  Object? dashboardError,
  bool settle = true,
  bool syncing = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        backendHealthProvider.overrideWith((ref) async {}),
        if (syncing)
          syncControllerProvider.overrideWith(_SyncingController.new),
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
      child: const MaterialApp(
        home: AppShell(userId: 'user-id', username: 'tester'),
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
  upcomingReminders: [
    UpcomingReminder(
      habitId: 'habit-id',
      habitName: 'Evening walk',
      scheduledAt: DateTime(2026, 1, 5, 18, 30),
    ),
  ],
);
