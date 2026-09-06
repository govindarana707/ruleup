import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/app/app.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/auth/data/auth_repository.dart';
import 'package:ruleup/features/auth/domain/auth_user.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/habits/presentation/habit_management_provider.dart';
import 'package:ruleup/features/check_ins/presentation/daily_check_in_provider.dart';
import 'package:ruleup/features/home/presentation/home_dashboard_provider.dart';
import 'package:ruleup/features/rewards/presentation/rewards_wallet_provider.dart';

void main() {
  testWidgets('authenticated RuleUp app renders Home', (tester) async {
    final synchronizedUsers = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          backendHealthProvider.overrideWith((ref) async {}),
          homeDashboardProvider.overrideWith((ref, _) async => _emptyDashboard),
          habitCatalogProvider.overrideWith(
            (ref, _) async => const HabitCatalog(habits: [], categories: []),
          ),
          dailyCheckInProvider.overrideWith(
            (ref, _) async =>
                DailyCheckInData(date: DateTime(2026, 1, 1), habits: const []),
          ),
          rewardsWalletProvider.overrideWith((ref, _) async => _emptyRewards),
          homeNowProvider.overrideWithValue(DateTime(2026, 1, 1, 9)),
          syncLifecycleTriggerProvider.overrideWithValue((userId) async {
            synchronizedUsers.add(userId);
          }),
        ],
        child: const RuleUpApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Good morning'), findsOneWidget);
    expect(find.text('tester'), findsOneWidget);
    expect(find.text('No habits yet'), findsOneWidget);
    expect(synchronizedUsers, ['user-id']);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(synchronizedUsers, ['user-id', 'user-id']);
  });

  testWidgets('authenticated dashboard shows offline state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          backendHealthProvider.overrideWith(
            (ref) => Future<void>.error(Exception('unreachable')),
          ),
          homeDashboardProvider.overrideWith((ref, _) async => _emptyDashboard),
          habitCatalogProvider.overrideWith(
            (ref, _) async => const HabitCatalog(habits: [], categories: []),
          ),
          dailyCheckInProvider.overrideWith(
            (ref, _) async =>
                DailyCheckInData(date: DateTime(2026, 1, 1), habits: const []),
          ),
          rewardsWalletProvider.overrideWith((ref, _) async => _emptyRewards),
          syncLifecycleTriggerProvider.overrideWithValue((_) async {}),
        ],
        child: const RuleUpApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Offline'), findsOneWidget);
    expect(
      find.text('Changes stay on this device and will sync when reconnected.'),
      findsOneWidget,
    );
  });
}

const _emptyDashboard = HomeDashboardData(
  availablePoints: 0,
  currentStreak: 0,
  completedToday: 0,
  applicableToday: 0,
  activeHabitCount: 0,
);

const _emptyRewards = RewardsWalletData(
  availablePoints: 0,
  lifetimeEarned: 0,
  spentPoints: 0,
  rewards: [],
);

class _SignedInRepository implements AuthRepository {
  @override
  Future<AuthUser?> restoreSession() async =>
      const AuthUser(id: 'user-id', username: 'tester');
  @override
  Future<AuthUser> login(String username, String password) =>
      throw UnimplementedError();
  @override
  Future<AuthUser> signup(String username, String password) =>
      throw UnimplementedError();
  @override
  Future<void> logout() async {}
}
