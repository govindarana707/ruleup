import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/home/presentation/home_dashboard.dart';

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
      const _ShellPlaceholder(
        icon: Icons.track_changes_outlined,
        title: 'Habits',
        message: 'Your habit management workspace is ready for the next phase.',
      ),
      const _ShellPlaceholder(
        icon: Icons.add_task_outlined,
        title: 'Check-in',
        message: 'The focused daily check-in experience will live here.',
      ),
      const _ShellPlaceholder(
        icon: Icons.card_giftcard_outlined,
        title: 'Rewards',
        message: 'Reward management and redemption will live here.',
      ),
      const _ShellPlaceholder(
        icon: Icons.history_outlined,
        title: 'History',
        message: 'Your activity history will live here.',
      ),
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

class _ShellPlaceholder extends StatelessWidget {
  const _ShellPlaceholder({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      key: Key('shell-page-${title.toLowerCase()}'),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 44,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
