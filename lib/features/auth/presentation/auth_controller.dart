import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:ruleup/core/config/app_config.dart';
import 'package:ruleup/core/database/database_provider.dart';
import 'package:ruleup/core/network/api_client.dart';
import 'package:ruleup/features/auth/data/auth_repository.dart';
import 'package:ruleup/features/auth/data/local_user_store.dart';
import 'package:ruleup/features/auth/data/token_storage.dart';
import 'package:ruleup/features/auth/domain/auth_user.dart';

final apiBaseUrlProvider = Provider<Uri>((ref) => AppConfig.apiBaseUrl);
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    ref.watch(apiBaseUrlProvider),
    ref.watch(httpClientProvider),
  );
});
final backendHealthProvider = FutureProvider<void>((ref) {
  return ref.watch(apiClientProvider).checkHealth();
});
final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => SecureTokenStorage(),
);
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return ApiAuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(tokenStorageProvider),
    DriftLocalUserStore(ref.watch(databaseProvider)),
  );
});

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthUser?>(
  AuthController.new,
);

class AuthController extends AsyncNotifier<AuthUser?> {
  @override
  Future<AuthUser?> build() =>
      ref.read(authRepositoryProvider).restoreSession();

  Future<void> login(String username, String password) => _authenticate(
    () => ref.read(authRepositoryProvider).login(username, password),
  );

  Future<void> signup(String username, String password) => _authenticate(
    () => ref.read(authRepositoryProvider).signup(username, password),
  );

  Future<void> logout() async {
    state = const AsyncLoading();
    await ref.read(authRepositoryProvider).logout();
    state = const AsyncData(null);
  }

  Future<void> _authenticate(Future<AuthUser> Function() action) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(action);
  }
}
