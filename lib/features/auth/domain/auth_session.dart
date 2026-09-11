import 'package:ruleup/features/auth/domain/auth_user.dart';

/// Provider-neutral authenticated session used at the data boundary.
class AuthSession {
  const AuthSession({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final AuthUser user;
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  bool get isExpired => !expiresAt.isAfter(DateTime.now().toUtc());
}
