import 'package:ruleup/core/network/api_client.dart';
import 'package:ruleup/features/auth/data/local_user_store.dart';
import 'package:ruleup/features/auth/data/token_storage.dart';
import 'package:ruleup/features/auth/domain/auth_user.dart';

abstract interface class AuthRepository {
  Future<AuthUser> signup(String username, String password);
  Future<AuthUser> login(String username, String password);
  Future<AuthUser?> restoreSession();
  Future<void> logout();
}

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._api, this._tokens, this._localUsers);

  final ApiClient _api;
  final TokenStorage _tokens;
  final LocalUserStore _localUsers;

  @override
  Future<AuthUser> signup(String username, String password) =>
      _authenticate('/auth/signup', username, password);

  @override
  Future<AuthUser> login(String username, String password) =>
      _authenticate('/auth/login', username, password);

  @override
  Future<AuthUser?> restoreSession() async {
    final token = await _tokens.read();
    if (token == null) return null;
    try {
      final response = await _api.get('/auth/me', token: token);
      final user = _readUser(response);
      await _localUsers.ensureExists(user.id);
      return user;
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _tokens.delete();
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
    return user;
  }

  AuthUser _readUser(Map<String, dynamic> response) {
    final data = response['data'] as Map<String, dynamic>;
    return AuthUser.fromJson(data['user'] as Map<String, dynamic>);
  }
}
