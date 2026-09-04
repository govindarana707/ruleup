import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ruleup/core/network/api_client.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/features/auth/data/auth_repository.dart';
import 'package:ruleup/features/auth/data/local_user_store.dart';
import 'package:ruleup/features/auth/data/token_storage.dart';
import 'package:ruleup/features/auth/domain/auth_user.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/auth/presentation/login_screen.dart';

void main() {
  test('health check accepts the backend health response', () async {
    final client = ApiClient(
      Uri.parse('https://ruleup.test'),
      MockClient((request) async {
        expect(request.url.path, '/health');
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      }),
    );

    await expectLater(client.checkHealth(), completes);
  });

  test('health check rejects an unreachable backend', () async {
    final client = ApiClient(
      Uri.parse('https://ruleup.test'),
      MockClient((_) async => throw http.ClientException('offline')),
    );

    await expectLater(
      client.checkHealth(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'network_error',
        ),
      ),
    );
  });

  test('login and signup validators reject invalid values', () {
    expect(validateUsername('ab'), isNotNull);
    expect(validateUsername('valid_user'), isNull);
    expect(validatePassword('short'), isNotNull);
    expect(validatePassword('long-enough-password'), isNull);
  });

  test('successful mocked login stores token securely', () async {
    final tokens = _MemoryTokenStorage();
    final repository = _repository(tokens, (request) async {
      expect(request.url.path, '/auth/login');
      return _authResponse();
    });

    final user = await repository.login('tester', 'long-enough-password');
    expect(user.username, 'tester');
    expect(tokens.token, 'secure-session-token');
  });

  test('successful mocked signup stores token securely', () async {
    final tokens = _MemoryTokenStorage();
    final repository = _repository(tokens, (_) async => _authResponse());
    await repository.signup('tester', 'long-enough-password');
    expect(tokens.token, 'secure-session-token');
  });

  test('secure token restore verifies session and returns its user', () async {
    final tokens = _MemoryTokenStorage()..token = 'secure-session-token';
    final repository = _repository(tokens, (request) async {
      expect(request.url.path, '/auth/me');
      expect(request.headers['authorization'], 'Bearer secure-session-token');
      return http.Response(
        jsonEncode({
          'data': {
            'user': {'id': 'user-id', 'username': 'tester'},
          },
        }),
        200,
      );
    });

    final user = await repository.restoreSession();
    expect(user?.id, 'user-id');
    expect(tokens.token, 'secure-session-token');
  });

  test('authenticated backend user is provisioned for local sync', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = _repository(
      _MemoryTokenStorage(),
      (_) async => _authResponse(),
      localUsers: DriftLocalUserStore(database),
    );

    await repository.login('tester', 'long-enough-password');

    final localUser = await database.select(database.localUsers).getSingle();
    expect(localUser.id, 'user-id');
  });

  test('logout calls backend and clears secure session', () async {
    final tokens = _MemoryTokenStorage()..token = 'secure-session-token';
    var called = false;
    final repository = _repository(tokens, (request) async {
      called =
          request.url.path == '/auth/logout' &&
          request.headers['authorization'] == 'Bearer secure-session-token';
      return http.Response(
        jsonEncode({
          'data': {'success': true},
        }),
        200,
      );
    });
    await repository.logout();
    expect(called, isTrue);
    expect(tokens.token, isNull);
  });

  test(
    'invalid stored session becomes unauthenticated and is cleared',
    () async {
      final tokens = _MemoryTokenStorage()..token = 'expired-token';
      final repository = _repository(
        tokens,
        (_) async => http.Response(
          jsonEncode({
            'error': {
              'code': 'unauthorized',
              'message': 'Authentication is required.',
            },
          }),
          401,
        ),
      );
      expect(await repository.restoreSession(), isNull);
      expect(tokens.token, isNull);
    },
  );

  test('auth state restores the signed-in user', () async {
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(_FakeRepository())],
    );
    addTearDown(container.dispose);
    final user = await container.read(authControllerProvider.future);
    expect(user?.username, 'tester');
  });
}

ApiAuthRepository _repository(
  TokenStorage tokens,
  Future<http.Response> Function(http.Request) handler, {
  LocalUserStore? localUsers,
}) => ApiAuthRepository(
  ApiClient(Uri.parse('https://ruleup.test'), MockClient(handler)),
  tokens,
  localUsers ?? _MemoryLocalUserStore(),
);

http.Response _authResponse() => http.Response(
  jsonEncode({
    'data': {
      'user': {'id': 'user-id', 'username': 'tester'},
      'token': 'secure-session-token',
    },
  }),
  200,
);

class _MemoryTokenStorage implements TokenStorage {
  String? token;
  @override
  Future<void> delete() async => token = null;
  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String token) async => this.token = token;
}

class _MemoryLocalUserStore implements LocalUserStore {
  @override
  Future<void> ensureExists(String userId) async {}
}

class _FakeRepository implements AuthRepository {
  @override
  Future<AuthUser?> restoreSession() async =>
      const AuthUser(id: 'user-id', username: 'tester');
  @override
  Future<AuthUser> login(String username, String password) async =>
      const AuthUser(id: 'user-id', username: 'tester');
  @override
  Future<AuthUser> signup(String username, String password) async =>
      const AuthUser(id: 'user-id', username: 'tester');
  @override
  Future<void> logout() async {}
}
