import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/app/app.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/auth/data/auth_repository.dart';
import 'package:ruleup/features/auth/domain/auth_user.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';

void main() {
  testWidgets('authenticated RuleUp app renders Home', (tester) async {
    final synchronizedUsers = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          backendHealthProvider.overrideWith((ref) async {}),
          syncLifecycleTriggerProvider.overrideWithValue((userId) async {
            synchronizedUsers.add(userId);
          }),
        ],
        child: const RuleUpApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome, tester'), findsOneWidget);
    expect(find.text('Foundation ready'), findsOneWidget);
    expect(synchronizedUsers, ['user-id']);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(synchronizedUsers, ['user-id', 'user-id']);
  });

  testWidgets('development shows an unreachable backend error', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          backendHealthProvider.overrideWith(
            (ref) => Future<void>.error(Exception('unreachable')),
          ),
          syncLifecycleTriggerProvider.overrideWithValue((_) async {}),
        ],
        child: const RuleUpApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cannot reach the RuleUp backend'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}

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
