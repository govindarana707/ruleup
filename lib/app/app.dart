import 'package:flutter/material.dart';
import 'package:ruleup/app/router/app_router.dart';
import 'package:ruleup/app/theme/app_theme.dart';

class RuleUpApp extends StatelessWidget {
  const RuleUpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RuleUp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      initialRoute: AppRouter.home,
      routes: AppRouter.routes,
    );
  }
}
