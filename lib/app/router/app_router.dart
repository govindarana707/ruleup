import 'package:flutter/widgets.dart';
import 'package:ruleup/features/auth/presentation/auth_gate.dart';

abstract final class AppRouter {
  static const home = '/';

  static final Map<String, WidgetBuilder> routes = {
    home: (_) => const AuthGate(),
  };
}
