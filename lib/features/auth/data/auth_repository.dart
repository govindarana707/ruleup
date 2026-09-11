import 'package:ruleup/core/network/api_client.dart';
import 'package:ruleup/features/auth/data/local_user_store.dart';
import 'package:ruleup/features/auth/data/token_storage.dart';
import 'package:ruleup/features/auth/data/supabase_auth_data_source.dart';
import 'package:ruleup/features/auth/domain/auth_session.dart';
import 'package:ruleup/features/auth/domain/auth_user.dart';

abstract interface class AuthRepository {
  Future<AuthUser> signup(String username, String password);
  Future<AuthUser> login(String username, String password);
  Future<AuthUser?> restoreSession();
  Future<void> logout();
}

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(
    this._api,
    this._tokens,
    this._localUsers, {
    this.supabaseAuth,
  });

  final ApiClient _api;
  final TokenStorage _tokens;
  final LocalUserStore _localUsers;
  final SupabaseAuthDataSource? supabaseAuth;

  @override
  Future<AuthUser> signup(String username, String password) =>
      _authenticate('/auth/signup', username, password);

  @override
  Future<AuthUser> login(String username, String password) =>
      _authenticate('/auth/login', username, password);

  @override
  Future<AuthUser?> restoreSession() async {
    final token = await _tokens.read();
    if (token == null) {
      await _clearSupabaseSession();
      return null;
    }
    try {
      final response = await _api.get('/auth/me', token: token);
      final user = _readUser(response);
      await _localUsers.ensureExists(user.id);
      try {
        await supabaseAuth?.restoreSession(expectedUser: user);
      } on Object {
        // Legacy restoration remains authoritative during the transition.
      }
      return user;
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _tokens.delete();
        await _clearSupabaseSession();
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<void> logout() async {
    final token = await _tokens.read();
    try {
      if (token != null) await _api.post('/auth/logout', token: token);
    } finally {
      await _tokens.delete();
      try {
        await supabaseAuth?.logout();
      } on Object {
        // Local legacy logout must succeed even if Supabase is unavailable.
      }
    }
  }

  Future<AuthUser> _authenticate(
    String path,
    String username,
    String password,
  ) async {
    final response = await _api.post(
      path,
      body: {'username': username, 'password': password},
    );
    final data = response['data'] as Map<String, dynamic>;
    final user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
    await _localUsers.ensureExists(user.id);
    await _tokens.write(data['token'] as String);
    final supabaseSession = data['supabaseSession'];
    if (supabaseSession is Map<String, dynamic>) {
      try {
        await supabaseAuth?.adoptTransitionSession(
          supabaseSession,
          expectedUser: user,
        );
      } on Object {
        // The verified legacy session is the safe fallback in Phase 2.
      }
    }
    return user;
  }

  AuthUser _readUser(Map<String, dynamic> response) {
    final data = response['data'] as Map<String, dynamic>;
    return AuthUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<void> _clearSupabaseSession() async {
    try {
      await supabaseAuth?.logout();
    } on Object {
      // Supabase state cannot override the legacy authenticated-user state.
    }
  }
}

/// Production repository. It deliberately has no Worker/D1 dependency so a
/// production build cannot accidentally dual-write or silently fall back.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._supabase, this._localUsers, this._legacyTokens);

  final SupabaseProductionAuthDataSource _supabase;
  final LocalUserStore _localUsers;
  final TokenStorage _legacyTokens;

  @override
  Future<AuthUser> signup(String username, String password) =>
      _authenticate(() => _supabase.signup(username, password));

  @override
  Future<AuthUser> login(String username, String password) =>
      _authenticate(() => _supabase.login(username, password));

  @override
  Future<AuthUser?> restoreSession() async {
    final session = await _supabase.restoreCurrentSession();
    if (session == null) return null;
    await _localUsers.ensureExists(session.user.id);
    return session.user;
  }

  @override
  Future<void> logout() async {
    try {
      await _supabase.logout();
    } finally {
      await _legacyTokens.delete();
    }
  }

  Future<AuthUser> _authenticate(Future<AuthSession> Function() action) async {
    final session = await action();
    await _localUsers.ensureExists(session.user.id);
    await _legacyTokens.delete();
    return session.user;
  }
}
