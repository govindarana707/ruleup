import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/auth/presentation/signup_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.errorMessage});
  final String? errorMessage;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RuleUp')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Login',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _username,
                  decoration: const InputDecoration(labelText: 'Username'),
                  validator: validateUsername,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  validator: validatePassword,
                ),
                if (widget.errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    widget.errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      ref
                          .read(authControllerProvider.notifier)
                          .login(_username.text, _password.text);
                    }
                  },
                  child: const Text('Login'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SignupScreen(),
                    ),
                  ),
                  child: const Text('Create account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String? validateUsername(String? value) {
  final username = value?.trim() ?? '';
  return RegExp(r'^[A-Za-z0-9_]{3,30}$').hasMatch(username)
      ? null
      : 'Use 3–30 letters, numbers, or underscores.';
}

String? validatePassword(String? value) =>
    value != null && value.length >= 12 && value.length <= 128
    ? null
    : 'Password must be 12–128 characters.';
