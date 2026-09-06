import 'package:flutter/widgets.dart';
import 'package:ruleup/features/home/presentation/app_shell.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.userId, required this.username});

  final String userId;
  final String username;

  @override
  Widget build(BuildContext context) =>
      AppShell(userId: userId, username: username);
}
