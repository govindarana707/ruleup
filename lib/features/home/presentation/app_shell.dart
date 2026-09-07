import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/check_ins/presentation/daily_check_in_screen.dart';
import 'package:ruleup/features/habits/presentation/habit_list_screen.dart';
import 'package:ruleup/features/home/presentation/home_dashboard.dart';
import 'package:ruleup/features/history/presentation/history_screen.dart';
import 'package:ruleup/features/rewards/presentation/rewards_wallet_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.userId, required this.username});

  final String userId;
  final String username;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  var _selectedIndex = 0;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.track_changes_outlined),
      selectedIcon: Icon(Icons.track_changes),
      label: 'Habits',
    ),
    NavigationDestination(
      icon: Icon(Icons.add_task_outlined),
      selectedIcon: Icon(Icons.add_task),
      label: 'Check-in',
    ),
    NavigationDestination(
      icon: Icon(Icons.card_giftcard_outlined),
      selectedIcon: Icon(Icons.card_giftcard),
      label: 'Rewards',
    ),
    NavigationDestination(
      icon: Icon(Icons.history_outlined),
      selectedIcon: Icon(Icons.history),
      label: 'History',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeDashboard(
        userId: widget.userId,
        username: widget.username,
        onQuickCheckIn: () => _select(2),
      ),
      HabitListScreen(userId: widget.userId),
      DailyCheckInScreen(userId: widget.userId),
      RewardsWalletScreen(userId: widget.userId),
      HistoryScreen(userId: widget.userId),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('RuleUp'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        key: const Key('app-bottom-navigation'),
        selectedIndex: _selectedIndex,
        onDestinationSelected: _select,
        destinations: _destinations,
      ),
    );
  }

  void _select(int index) => setState(() => _selectedIndex = index);
}
