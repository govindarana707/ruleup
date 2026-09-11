import 'package:ruleup/features/auth/data/supabase_session_storage.dart';
import 'package:ruleup/features/auth/domain/auth_session.dart';
import 'package:ruleup/features/auth/domain/auth_user.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

abstract interface class SupabaseAuthDataSource {
  Future<AuthSession> adoptTransitionSession(
    Map<String, dynamic> payload, {
    required AuthUser expectedUser,
  });
  Future<AuthSession?> restoreSession({required AuthUser expectedUser});
  Future<void> logout();
}

class SupabaseAuthDataSourceImpl implements SupabaseAuthDataSource {
  SupabaseAuthDataSourceImpl(this._client, this._storage);

  final SupabaseClient _client;
  final SupabaseSessionStorage _storage;

  @override
  Future<AuthSession> adoptTransitionSession(
    Map<String, dynamic> payload, {
    required AuthUser expectedUser,
  }) async {
    final envelope = _SessionEnvelope.fromJson(payload);
    if (envelope.userId != expectedUser.id) {
      throw const FormatException(
        'Supabase session user does not match RuleUp user.',
      );
    }
    return _establish(envelope, expectedUser);
  }

  @override
  Future<AuthSession?> restoreSession({required AuthUser expectedUser}) async {
    final stored = await _storage.read();
    if (stored == null) return null;
    try {
      final envelope = _SessionEnvelope.fromJson(stored);
      if (envelope.userId != expectedUser.id) {
        await _storage.delete();
        return null;
      }
      return await _establish(envelope, expectedUser);
    } on AuthException {
      await _storage.delete();
      return null;
    } on FormatException {
      await _storage.delete();
      return null;
    }
  }

  @override
  Future<void> logout() async {
    await _clearLocalSession();
  }

  Future<void> _clearLocalSession() async {
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } finally {
      await _storage.delete();
    }
  }

  Future<AuthSession> _establish(
    _SessionEnvelope envelope,
    AuthUser expectedUser,
  ) async {
    final response = await _client.auth.setSession(
      envelope.refreshToken,
      accessToken: envelope.accessToken,
    );
    final session = response.session;
    if (session == null || session.user.id != expectedUser.id) {
      await _clearLocalSession();
      throw const FormatException('Supabase returned an unexpected identity.');
    }
    final mapped = SupabaseSessionMapper.map(session, expectedUser.username);
    await _storage.write({
      'accessToken': mapped.accessToken,
      'refreshToken': mapped.refreshToken,
      'expiresAt': mapped.expiresAt.millisecondsSinceEpoch ~/ 1000,
      'userId': mapped.user.id,
    });
    return mapped;
  }
}

abstract final class SupabaseSessionMapper {
  static AuthSession map(Session session, String username) {
    final refreshToken = session.refreshToken;
    final expiresAt = session.expiresAt;
    if (refreshToken == null || expiresAt == null) {
      throw const FormatException('Supabase session is incomplete.');
    }
    return AuthSession(
      user: AuthUser(id: session.user.id, username: username),
      accessToken: session.accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        expiresAt * 1000,
        isUtc: true,
      ),
    );
  }
}

class _SessionEnvelope {
  const _SessionEnvelope({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.userId,
  });

  factory _SessionEnvelope.fromJson(Map<String, dynamic> json) {
    final accessToken = json['accessToken'];
    final refreshToken = json['refreshToken'];
    final expiresAt = json['expiresAt'];
    final userId = json['userId'];
    if (accessToken is! String ||
        accessToken.isEmpty ||
        refreshToken is! String ||
        refreshToken.isEmpty ||
        expiresAt is! num ||
        userId is! String) {
      throw const FormatException('Invalid Supabase session payload.');
    }
    return _SessionEnvelope(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt.toInt(),
      userId: userId,
    );
  }

  final String accessToken;
  final String refreshToken;
  final int expiresAt;
  final String userId;
}
