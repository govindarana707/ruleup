import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/auth/data/auth_repository.dart';
import 'package:ruleup/features/auth/domain/auth_user.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/auth/presentation/auth_gate.dart';
import 'package:ruleup/features/auth/presentation/splash_screen.dart';

void main() {
  testWidgets('splash keeps branding visible on a compact phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
    await tester.pump();

    expect(find.text('RuleUp'), findsOneWidget);
    expect(find.text('BUILD A BETTER YOU'), findsOneWidget);
    expect(find.text('Getting things ready...'), findsOneWidget);
    expect(find.text('SMALL STEPS\nBIG CHANGES'), findsOneWidget);
    expect(find.text('Developed by'), findsOneWidget);
    expect(find.text('Govinda Rana'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auth gate renders splash before restoring the session', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_PendingRepository()),
          backendHealthProvider.overrideWith((ref) async {}),
          syncLifecycleTriggerProvider.overrideWithValue((_) async {}),
        ],
        child: const MaterialApp(home: AuthGate()),
      ),
    );

    expect(find.byType(SplashScreen), findsOneWidget);
    await tester.pump();
    expect(find.text('Getting things ready...'), findsOneWidget);
  });
}

class _PendingRepository implements AuthRepository {
  final _session = Completer<AuthUser?>();

  @override
  Future<AuthUser?> restoreSession() => _session.future;

  @override
  Future<AuthUser> login(String username, String password) =>
      throw UnimplementedError();

  @override
  Future<AuthUser> signup(String username, String password) =>
      throw UnimplementedError();

  @override
  Future<void> logout() async {}
}
