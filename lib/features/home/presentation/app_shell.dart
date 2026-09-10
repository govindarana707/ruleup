import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/features/check_ins/presentation/daily_check_in_screen.dart';
import 'package:ruleup/features/habits/presentation/habit_list_screen.dart';
import 'package:ruleup/features/home/presentation/home_dashboard.dart';
import 'package:ruleup/features/home/presentation/home_dashboard_theme.dart';
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
      selectedIcon: _HomeSelectedIcon(),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.eco_outlined),
      selectedIcon: Icon(Icons.eco_rounded),
      label: 'Habits',
    ),
    NavigationDestination(
      icon: _CheckInNavIcon(),
      selectedIcon: _CheckInNavIcon(selected: true),
      label: 'Check-in',
    ),
    NavigationDestination(
      icon: Icon(Icons.card_giftcard_outlined),
      selectedIcon: Icon(Icons.card_giftcard_rounded),
      label: 'Rewards',
    ),
    NavigationDestination(
      icon: Icon(Icons.history_outlined),
      selectedIcon: Icon(Icons.history_rounded),
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
    final usesDashboardTheme =
        _selectedIndex == 0 || _selectedIndex == 1 || _selectedIndex == 2;
    return Theme(
      data: usesDashboardTheme
          ? HomeDashboardTheme.create()
          : Theme.of(context),
      child: Scaffold(
        appBar: _selectedIndex <= 2
            ? null
            : AppBar(
                title: const Text(
                  'RuleUp',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                actions: [
                  IconButton(
                    key: const Key('open-settings'),
                    tooltip: 'Settings',
                    onPressed: _openSettings,
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
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: HomeDashboardTheme.outline)),
          ),
          child: NavigationBar(
            key: const Key('app-bottom-navigation'),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            selectedIndex: _selectedIndex,
            onDestinationSelected: _select,
            destinations: _destinations,
          ),
        ),
      ),
    );
  }

  Widget _buildPage(int index) => switch (index) {
    0 => HomeDashboard(
      userId: widget.userId,
      username: widget.username,
      onQuickCheckIn: () => _select(2),
      onOpenSettings: _openSettings,
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

  void _openSettings() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          SettingsScreen(userId: widget.userId, username: widget.username),
    ),
  );
}

class _HomeSelectedIcon extends StatelessWidget {
  const _HomeSelectedIcon();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.home_rounded),
        const SizedBox(height: 3),
        Container(
          width: 20,
          height: 3,
          decoration: BoxDecoration(
            color: HomeDashboardTheme.mint,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ],
    );
  }
}

class _CheckInNavIcon extends StatelessWidget {
  const _CheckInNavIcon({this.selected = false});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: selected
            ? HomeDashboardTheme.mint
            : HomeDashboardTheme.surfaceRaised,
        shape: BoxShape.circle,
        border: Border.all(color: HomeDashboardTheme.outline),
      ),
      child: Icon(
        Icons.add_rounded,
        color: selected ? const Color(0xFF052019) : HomeDashboardTheme.text,
      ),
    );
  }
}
