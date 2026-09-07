import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/app/theme/app_theme.dart';
import 'package:ruleup/features/auth/domain/auth_user.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/auth/presentation/signup_screen.dart';

void main() {
  testWidgets('sign up remains scrollable with keyboard and larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_SignedOutController.new),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const SignupScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.showKeyboard(find.byType(TextFormField).last);
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('signup-submit-button')));
    await tester.pump();

    expect(find.byKey(const Key('signup-submit-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _SignedOutController extends AuthController {
  @override
  Future<AuthUser?> build() async => null;
}
