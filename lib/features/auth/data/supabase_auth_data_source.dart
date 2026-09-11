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

abstract interface class SupabaseProductionAuthDataSource {
  Future<AuthSession> signup(String username, String password);
  Future<AuthSession> login(String username, String password);
  Future<AuthSession?> restoreCurrentSession();
  Future<void> logout();
}

class SupabaseAuthDataSourceImpl
    implements SupabaseAuthDataSource, SupabaseProductionAuthDataSource {
  SupabaseAuthDataSourceImpl(this._client, this._storage);

  final SupabaseClient _client;
  final SupabaseSessionStorage _storage;

  @override
  Future<AuthSession> signup(String username, String password) =>
      _authenticate('signup', username, password);

  @override
  Future<AuthSession> login(String username, String password) =>
      _authenticate('login', username, password);

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
  Future<AuthSession?> restoreCurrentSession() async {
    final stored = await _storage.read();
    if (stored == null) return null;
    try {
      final envelope = _SessionEnvelope.fromJson(stored);
      final response = await _client.auth.setSession(
        envelope.refreshToken,
        accessToken: envelope.accessToken,
      );
      final session = response.session;
      if (session == null || session.user.id != envelope.userId) {
        await _clearLocalSession();
        return null;
      }
      var username = envelope.username;
      if (username == null) {
        final profile = await _client
            .from('profiles')
            .select('username')
            .eq('id', envelope.userId)
            .single();
        final remoteUsername = profile['username'];
        if (remoteUsername is! String) {
          throw const FormatException('Supabase profile is incomplete.');
        }
        username = remoteUsername;
      }
      final mapped = SupabaseSessionMapper.map(session, username);
      await _store(mapped);
      return mapped;
    } on AuthException {
      await _clearLocalSession();
      return null;
    } on FormatException {
      await _clearLocalSession();
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
    await _store(mapped);
    return mapped;
  }

  Future<AuthSession> _authenticate(
    String action,
    String username,
    String password,
  ) async {
    final response = await _client.functions.invoke(
      'username-auth',
      body: {'action': action, 'username': username, 'password': password},
    );
    if (response.status < 200 || response.status >= 300) {
      throw AuthException('Supabase authentication failed.');
    }
    final payload = response.data;
    if (payload is! Map) {
      throw const FormatException('Invalid Supabase authentication response.');
    }
    final data = payload['data'];
    if (data is! Map) {
      throw const FormatException('Invalid Supabase authentication response.');
    }
    final rawUser = data['user'];
    final rawSession = data['supabaseSession'];
    if (rawUser is! Map || rawSession is! Map) {
      throw const FormatException('Invalid Supabase authentication response.');
    }
    final user = AuthUser.fromJson(Map<String, dynamic>.from(rawUser));
    final session = await adoptTransitionSession(
      Map<String, dynamic>.from(rawSession),
      expectedUser: user,
    );
    if (session.user.username != username.trim().toLowerCase()) {
      throw const FormatException('Supabase returned an unexpected username.');
    }
    return session;
  }

  Future<void> _store(AuthSession session) => _storage.write({
    'accessToken': session.accessToken,
    'refreshToken': session.refreshToken,
    'expiresAt': session.expiresAt.millisecondsSinceEpoch ~/ 1000,
    'userId': session.user.id,
    'username': session.user.username,
  });
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
    this.username,
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
      username: json['username'] is String ? json['username'] as String : null,
    );
  }

  final String accessToken;
  final String refreshToken;
  final int expiresAt;
  final String userId;
  final String? username;
}
