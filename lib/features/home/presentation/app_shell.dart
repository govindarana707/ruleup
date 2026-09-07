import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/features/check_ins/presentation/daily_check_in_screen.dart';
import 'package:ruleup/features/habits/presentation/habit_list_screen.dart';
import 'package:ruleup/features/home/presentation/home_dashboard.dart';
import 'package:ruleup/features/history/presentation/history_screen.dart';
import 'package:ruleup/features/rewards/presentation/rewards_wallet_screen.dart';
import 'package:ruleup/features/settings/presentation/settings_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.userId, required this.username});

  final String userId;
  final String username;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  var _selectedIndex = 0;
  late final List<Widget?> _pages;

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
  void initState() {
    super.initState();
    _pages = List<Widget?>.filled(_destinations.length, null);
    _pages[0] = _buildPage(0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RuleUp'),
        actions: [
          IconButton(
            key: const Key('open-settings'),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SettingsScreen(
                  userId: widget.userId,
                  username: widget.username,
                ),
              ),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: HeroMode(
        enabled: false,
        child: IndexedStack(
          index: _selectedIndex,
          children: _pages
              .map((page) => page ?? const SizedBox.shrink())
              .toList(growable: false),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        key: const Key('app-bottom-navigation'),
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        selectedIndex: _selectedIndex,
        onDestinationSelected: _select,
        destinations: _destinations,
      ),
    );
  }

  Widget _buildPage(int index) => switch (index) {
    0 => HomeDashboard(
      userId: widget.userId,
      username: widget.username,
      onQuickCheckIn: () => _select(2),
    ),
    1 => HabitListScreen(userId: widget.userId),
    2 => DailyCheckInScreen(userId: widget.userId),
    3 => RewardsWalletScreen(userId: widget.userId),
    4 => HistoryScreen(userId: widget.userId),
    _ => throw RangeError.index(index, _destinations),
  };

  void _select(int index) => setState(() {
    _pages[index] ??= _buildPage(index);
    _selectedIndex = index;
  });
}
