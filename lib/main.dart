import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/app/app.dart';
import 'package:ruleup/core/config/app_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.validateStartupConfiguration();
  runApp(const ProviderScope(child: RuleUpApp()));
}
