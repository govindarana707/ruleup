import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/network/api_client.dart';
import 'package:ruleup/core/config/app_config.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/auth/presentation/login_screen.dart';
import 'package:ruleup/features/home/presentation/home_screen.dart';

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate>
    with WidgetsBindingObserver {
  String? _activeUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    ref.read(authControllerProvider).whenData((user) {
      if (user != null) unawaited(_synchronize(user.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    final backendHealth = ref.watch(backendHealthProvider);
    final auth = ref.watch(authControllerProvider);
    auth.whenData((user) {
      if (user == null) {
        _activeUserId = null;
      } else if (_activeUserId != user.id) {
        _activeUserId = user.id;
        unawaited(_synchronize(user.id));
      }
    });

    if (AppConfig.showDevelopmentConnectionErrors &&
        backendHealth.hasError &&
        auth.asData?.value == null) {
      return _DevelopmentConnectionError(
        onRetry: () => ref.invalidate(backendHealthProvider),
      );
    }

    return auth.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      data: (user) => user == null
          ? const LoginScreen()
          : HomeScreen(userId: user.id, username: user.username),
      error: (error, _) => LoginScreen(errorMessage: _message(error)),
    );
  }

  String _message(Object error) => error is ApiException
      ? error.message
      : 'Something went wrong. Please try again.';

  Future<void> _synchronize(String userId) =>
      ref.read(syncLifecycleTriggerProvider)(userId);
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
