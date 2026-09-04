import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.username});

  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RuleUp'),
        actions: [
          TextButton(
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            child: const Text('Logout'),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Welcome, $username',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text('Foundation ready'),
          ],
        ),
      ),
    );
  }
}
