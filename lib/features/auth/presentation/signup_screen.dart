import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/network/api_client.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/auth/presentation/login_screen.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});
  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
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
    ref.listen(authControllerProvider, (_, next) {
      if (next.hasValue &&
          next.value != null &&
          Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Sign Up')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
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
              if (auth.hasError) ...[
                const SizedBox(height: 12),
                Text(
                  auth.error is ApiException
                      ? (auth.error! as ApiException).message
                      : 'Could not create account. Please try again.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: auth.isLoading
                    ? null
                    : () {
                        if (_formKey.currentState!.validate()) {
                          ref
                              .read(authControllerProvider.notifier)
                              .signup(_username.text, _password.text);
                        }
                      },
                child: const Text('Create account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
