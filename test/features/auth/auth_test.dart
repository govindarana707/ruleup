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
import 'package:ruleup/features/auth/data/supabase_auth_data_source.dart';
import 'package:ruleup/features/auth/data/token_storage.dart';
import 'package:ruleup/features/auth/domain/auth_session.dart';
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

  test(
    'login adopts an optional matching Supabase transition session',
    () async {
      final supabase = _FakeSupabaseAuthDataSource();
      final repository = _repository(
        _MemoryTokenStorage(),
        (_) => Future.value(_authResponse(withSupabaseSession: true)),
        supabaseAuth: supabase,
      );

      final user = await repository.login('tester', 'long-enough-password');

      expect(supabase.adoptedFor?.id, user.id);
      expect(supabase.adoptedPayload?['userId'], user.id);
    },
  );

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

  test(
    'legacy restoration also restores the optional Supabase session',
    () async {
      final tokens = _MemoryTokenStorage()..token = 'secure-session-token';
      final supabase = _FakeSupabaseAuthDataSource();
      final repository = _repository(
        tokens,
        (_) async => http.Response(
          jsonEncode({
            'data': {
              'user': {'id': 'user-id', 'username': 'tester'},
            },
          }),
          200,
        ),
        supabaseAuth: supabase,
      );

      await repository.restoreSession();

      expect(supabase.restoredFor?.id, 'user-id');
    },
  );

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

  test(
    'production Supabase auth provisions Drift and clears legacy token',
    () async {
      final tokens = _MemoryTokenStorage()..token = 'legacy-token';
      final localUsers = _TrackingLocalUserStore();
      final repository = SupabaseAuthRepository(
        _FakeProductionSupabaseAuth(),
        localUsers,
        tokens,
      );

      final user = await repository.login('tester', 'long-enough-password');

      expect(user.id, 'user-id');
      expect(localUsers.userId, 'user-id');
      expect(tokens.token, isNull);
    },
  );

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

  test('logout clears both legacy and Supabase session state', () async {
    final tokens = _MemoryTokenStorage()..token = 'secure-session-token';
    final supabase = _FakeSupabaseAuthDataSource();
    final repository = _repository(
      tokens,
      (_) => Future.value(
        http.Response(
          jsonEncode({
            'data': {'success': true},
          }),
          200,
        ),
      ),
      supabaseAuth: supabase,
    );

    await repository.logout();

    expect(tokens.token, isNull);
    expect(supabase.loggedOut, isTrue);
  });

  test(
    'invalid stored session becomes unauthenticated and is cleared',
    () async {
      final tokens = _MemoryTokenStorage()..token = 'expired-token';
      final supabase = _FakeSupabaseAuthDataSource();
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
        supabaseAuth: supabase,
      );
      expect(await repository.restoreSession(), isNull);
      expect(tokens.token, isNull);
      expect(supabase.loggedOut, isTrue);
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
  SupabaseAuthDataSource? supabaseAuth,
}) => ApiAuthRepository(
  ApiClient(Uri.parse('https://ruleup.test'), MockClient(handler)),
  tokens,
  localUsers ?? _MemoryLocalUserStore(),
  supabaseAuth: supabaseAuth,
);

http.Response _authResponse({bool withSupabaseSession = false}) =>
    http.Response(
      jsonEncode({
        'data': {
          'user': {'id': 'user-id', 'username': 'tester'},
          'token': 'secure-session-token',
          if (withSupabaseSession)
            'supabaseSession': {
              'accessToken': 'access-token',
              'refreshToken': 'refresh-token',
              'expiresAt': 2000000000,
              'userId': 'user-id',
            },
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

class _TrackingLocalUserStore implements LocalUserStore {
  String? userId;
  @override
  Future<void> ensureExists(String userId) async => this.userId = userId;
}

class _FakeProductionSupabaseAuth implements SupabaseProductionAuthDataSource {
  AuthSession get _session => AuthSession(
    user: const AuthUser(id: 'user-id', username: 'tester'),
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    expiresAt: DateTime.utc(2030),
  );

  @override
  Future<AuthSession> login(String username, String password) async => _session;
  @override
  Future<AuthSession> signup(String username, String password) async =>
      _session;
  @override
  Future<AuthSession?> restoreCurrentSession() async => _session;
  @override
  Future<void> logout() async {}
}

class _FakeSupabaseAuthDataSource implements SupabaseAuthDataSource {
  Map<String, dynamic>? adoptedPayload;
  AuthUser? adoptedFor;
  AuthUser? restoredFor;
  bool loggedOut = false;

  @override
  Future<AuthSession> adoptTransitionSession(
    Map<String, dynamic> payload, {
    required AuthUser expectedUser,
  }) async {
    adoptedPayload = payload;
    adoptedFor = expectedUser;
    return AuthSession(
      user: expectedUser,
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      expiresAt: DateTime.fromMillisecondsSinceEpoch(2000000000000),
    );
  }

  @override
  Future<void> logout() async => loggedOut = true;

  @override
  Future<AuthSession?> restoreSession({required AuthUser expectedUser}) async {
    restoredFor = expectedUser;
    return null;
  }
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
