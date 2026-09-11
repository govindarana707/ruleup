import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ruleup/features/auth/data/supabase_auth_data_source.dart';
import 'package:ruleup/features/auth/data/supabase_session_storage.dart';
import 'package:ruleup/features/auth/domain/auth_user.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

void main() {
  const user = AuthUser(
    id: '11111111-1111-4111-8111-111111111111',
    username: 'tester',
  );

  test(
    'transition session maps to neutral app session and is persisted',
    () async {
      final storage = _MemorySupabaseSessionStorage();
      final accessToken = _jwt(user.id, 2000000000);
      final client = SupabaseClient(
        'https://project.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/auth/v1/user');
          expect(request.headers['authorization'], 'Bearer $accessToken');
          return http.Response(
            jsonEncode({
              'id': user.id,
              'aud': 'authenticated',
              'app_metadata': {},
              'user_metadata': {'username': user.username},
              'created_at': '2026-09-11T00:00:00Z',
            }),
            200,
          );
        }),
      );
      final source = SupabaseAuthDataSourceImpl(client, storage);

      final session = await source.adoptTransitionSession({
        'accessToken': accessToken,
        'refreshToken': 'refresh-token',
        'expiresAt': 2000000000,
        'userId': user.id,
      }, expectedUser: user);

      expect(session.user.id, user.id);
      expect(session.user.username, user.username);
      expect(session.refreshToken, 'refresh-token');
      expect(storage.value?['userId'], user.id);
      expect(storage.value.toString(), isNot(contains('service_role')));
    },
  );

  test(
    'mismatched restored identity is rejected and cleared offline',
    () async {
      final storage = _MemorySupabaseSessionStorage()
        ..value = {
          'accessToken': 'not-used',
          'refreshToken': 'not-used',
          'expiresAt': 2000000000,
          'userId': '22222222-2222-4222-8222-222222222222',
        };
      final source = SupabaseAuthDataSourceImpl(
        SupabaseClient('https://project.supabase.co', 'anon-key'),
        storage,
      );

      expect(await source.restoreSession(expectedUser: user), isNull);
      expect(storage.value, isNull);
    },
  );

  test(
    'invalid persisted session is cleared without real credentials',
    () async {
      final storage = _MemorySupabaseSessionStorage()
        ..value = {'invalid': true};
      final source = SupabaseAuthDataSourceImpl(
        SupabaseClient('https://project.supabase.co', 'anon-key'),
        storage,
      );

      expect(await source.restoreSession(expectedUser: user), isNull);
      expect(storage.value, isNull);
    },
  );

  test('expired access token refreshes and persists rotation', () async {
    final storage = _MemorySupabaseSessionStorage()
      ..value = {
        'accessToken': _jwt(user.id, 1),
        'refreshToken': 'old-refresh',
        'expiresAt': 1,
        'userId': user.id,
      };
    final refreshedAccessToken = _jwt(user.id, 2000000000);
    final client = SupabaseClient(
      'https://project.supabase.co',
      'anon-key',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/auth/v1/token');
        expect(request.url.queryParameters['grant_type'], 'refresh_token');
        return http.Response(
          jsonEncode({
            'access_token': refreshedAccessToken,
            'refresh_token': 'rotated-refresh',
            'expires_in': 100000000,
            'token_type': 'bearer',
            'user': {
              'id': user.id,
              'aud': 'authenticated',
              'app_metadata': {},
              'user_metadata': {'username': user.username},
              'created_at': '2026-09-11T00:00:00Z',
            },
          }),
          200,
        );
      }),
    );
    final source = SupabaseAuthDataSourceImpl(client, storage);

    final session = await source.restoreSession(expectedUser: user);

    expect(session?.accessToken, refreshedAccessToken);
    expect(storage.value?['refreshToken'], 'rotated-refresh');
  });
}

String _jwt(String subject, int expiry) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part({'sub': subject, 'exp': expiry, 'iat': 1900000000})}.';
}

class _MemorySupabaseSessionStorage implements SupabaseSessionStorage {
  Map<String, dynamic>? value;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<Map<String, dynamic>?> read() async => value;

  @override
  Future<void> write(Map<String, dynamic> session) async => value = session;
}
