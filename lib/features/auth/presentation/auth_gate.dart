import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/network/api_client.dart';
import 'package:ruleup/core/config/app_config.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/auth/presentation/login_screen.dart';
import 'package:ruleup/features/home/presentation/home_screen.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backendHealth = ref.watch(backendHealthProvider);
    final auth = ref.watch(authControllerProvider);

    if (AppConfig.showDevelopmentConnectionErrors && backendHealth.hasError) {
      return _DevelopmentConnectionError(
        onRetry: () => ref.invalidate(backendHealthProvider),
      );
    }

    return auth.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      data: (user) => user == null
          ? const LoginScreen()
          : HomeScreen(username: user.username),
      error: (error, _) => LoginScreen(errorMessage: _message(error)),
    );
  }

  String _message(Object error) => error is ApiException
      ? error.message
      : 'Something went wrong. Please try again.';
}

class _DevelopmentConnectionError extends StatelessWidget {
  const _DevelopmentConnectionError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Cannot reach the RuleUp backend',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Start the local Worker and verify ${AppConfig.apiBaseUrl}.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}
