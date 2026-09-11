import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ruleup/core/config/app_config.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/database/database_provider.dart';
import 'package:ruleup/core/database/database_uuid.dart';
import 'package:ruleup/core/network/api_client.dart';
import 'package:ruleup/core/supabase/supabase_database_service.dart';
import 'package:ruleup/core/supabase/supabase_provider.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/core/sync/sync_service.dart';
import 'package:ruleup/features/auth/data/token_storage.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/rewards/data/reward_repository.dart';
import 'package:ruleup/features/rewards/data/reward_repository_provider.dart';

final rewardImageServiceProvider = Provider<RewardImageService>((ref) {
  final useSupabase = AppConfig.habitSyncBackend == HabitSyncBackend.supabase;
  return RewardImageService(
    useSupabase ? null : ref.watch(apiClientProvider),
    useSupabase ? null : ref.watch(tokenStorageProvider),
    ref.watch(rewardRepositoryProvider),
    database: ref.watch(databaseProvider),
    sync: ref.watch(syncServiceProvider),
    supabase: ref.watch(supabaseDatabaseServiceProvider),
    useSupabase: useSupabase,
  );
});

class RewardImageService {
  RewardImageService(
    this._api,
    this._tokens,
    this._rewards, {
    required this._database,
    required this._sync,
    required this._supabase,
    required this._useSupabase,
  });
  final ApiClient? _api;
  final TokenStorage? _tokens;
  final RewardRepository _rewards;
  final AppDatabase _database;
  final SyncService _sync;
  final SupabaseDatabaseService? _supabase;
  final bool _useSupabase;

  Future<XFile?> pick() => ImagePicker().pickImage(
    source: ImageSource.gallery,
    imageQuality: 82,
    maxWidth: 1600,
    maxHeight: 1600,
    requestFullMetadata: false,
  );
  Future<void> replace({
    required String userId,
    required String rewardId,
    required String? oldKey,
    required XFile image,
  }) async {
    if (_useSupabase) {
      await _queueSupabaseReplacement(
        userId: userId,
        rewardId: rewardId,
        oldKey: oldKey,
        image: image,
      );
      return;
    }
    final token = await _tokens!.read();
    if (token == null) {
      throw const ApiException(
        statusCode: 0,
        code: 'unauthorized',
        message: 'Please sign in again.',
      );
    }
    final bytes = await image.readAsBytes();
    if (bytes.isEmpty || bytes.length > 1024 * 1024) {
      throw const ApiException(
        statusCode: 0,
        code: 'invalid_image',
        message: 'Choose a smaller image (up to 1 MB).',
      );
    }
    final mime = image.mimeType == 'image/webp' ? 'image/webp' : 'image/jpeg';
    final response = await _api!.postBytes(
      '/reward-images',
      bytes: bytes,
      contentType: mime,
      token: token,
    );
    final data = response['data'] as Map<String, dynamic>?;
    final key = data?['imageKey'] as String?;
    if (key == null) {
      throw const ApiException(
        statusCode: 0,
        code: 'invalid_response',
        message: 'Image upload failed.',
      );
    }
    await _rewards.setImageKey(userId, rewardId, key);
    if (oldKey != null && oldKey != key) {
      try {
        await _api.delete(
          '/reward-images/${Uri.encodeComponent(oldKey)}',
          token: token,
        );
      } on Object {
        // The new image key remains valid even if old-object cleanup is delayed.
      }
    }
  }

  Future<void> remove({
    required String userId,
    required String rewardId,
    required String key,
  }) async {
    if (_useSupabase) {
      _validateOwnedKey(userId, rewardId, key);
      await _database.transaction(() async {
        await _rewards.setImageKey(userId, rewardId, null);
        await _queueImageOperation(
          userId: userId,
          rewardId: rewardId,
          operation: 'delete',
          objectKey: key,
        );
      });
      return;
    }
    final token = await _tokens!.read();
    if (token == null) {
      throw const ApiException(
        statusCode: 0,
        code: 'unauthorized',
        message: 'Please sign in again.',
      );
    }
    await _rewards.setImageKey(userId, rewardId, null);
    try {
      await _api!.delete(
        '/reward-images/${Uri.encodeComponent(key)}',
        token: token,
      );
    } on Object {
      // The key is removed locally; cleanup can be retried server-side later.
    }
  }

  Future<void> _queueSupabaseReplacement({
    required String userId,
    required String rewardId,
    required String? oldKey,
    required XFile image,
  }) async {
    final bytes = await image.readAsBytes();
    if (bytes.isEmpty || bytes.length > 1024 * 1024) {
      throw const ApiException(
        statusCode: 0,
        code: 'invalid_image',
        message: 'Choose a smaller image (up to 1 MB).',
      );
    }
    final mime = _supportedMime(image);
    final extension = mime == 'image/webp' ? 'webp' : 'jpg';
    final objectKey = '$userId/$rewardId/${createDatabaseUuid()}.$extension';
    if (oldKey != null) _validateOwnedKey(userId, rewardId, oldKey);
    await _database.transaction(() async {
      await _queueImageOperation(
        userId: userId,
        rewardId: rewardId,
        operation: 'upload',
        objectKey: objectKey,
        bytes: bytes,
        mimeType: mime,
      );
      await _rewards.setImageKey(userId, rewardId, objectKey);
      if (oldKey != null && oldKey != objectKey) {
        await _queueImageOperation(
          userId: userId,
          rewardId: rewardId,
          operation: 'delete',
          objectKey: oldKey,
        );
      }
    });
  }

  Future<void> _queueImageOperation({
    required String userId,
    required String rewardId,
    required String operation,
    required String objectKey,
    List<int>? bytes,
    String? mimeType,
  }) async {
    final row = await _database
        .into(_database.rewardImageOperations)
        .insertReturning(
          RewardImageOperationsCompanion.insert(
            userId: userId,
            rewardId: rewardId,
            operation: operation,
            objectKey: objectKey,
            bytes: Value(bytes == null ? null : Uint8List.fromList(bytes)),
            mimeType: Value(mimeType),
          ),
        );
    await _sync.enqueue(
      userId: userId,
      entityType: operation == 'upload'
          ? 'reward_image_upload'
          : 'reward_image_delete',
      entityId: row.id,
      operation: operation,
    );
  }

  String _supportedMime(XFile image) {
    final supplied = image.mimeType?.toLowerCase();
    if (supplied == 'image/jpeg' || supplied == 'image/webp') return supplied!;
    final name = image.name.toLowerCase();
    if (supplied == null && (name.endsWith('.jpg') || name.endsWith('.jpeg'))) {
      return 'image/jpeg';
    }
    if (supplied == null && name.endsWith('.webp')) return 'image/webp';
    throw const ApiException(
      statusCode: 0,
      code: 'invalid_image',
      message: 'Choose a JPEG or WebP image.',
    );
  }

  void _validateOwnedKey(String userId, String rewardId, String key) {
    if (!key.startsWith('$userId/$rewardId/')) {
      throw const ApiException(
        statusCode: 0,
        code: 'invalid_image_key',
        message: 'The image does not belong to this reward.',
      );
    }
  }

  Future<RewardImageAccess?> access(String key) async {
    if (_useSupabase) {
      final service = _supabase;
      final userId = service?.client.auth.currentUser?.id;
      if (service == null || userId == null || !key.startsWith('$userId/')) {
        return null;
      }
      final signed = await service.client.storage
          .from('reward-images')
          .createSignedUrl(key, 300);
      return RewardImageAccess(Uri.parse(signed));
    }
    final token = await _tokens!.read();
    if (token == null) return null;
    return RewardImageAccess(
      _api!.resolve('/reward-images/${Uri.encodeComponent(key)}'),
      headers: {'authorization': 'Bearer $token'},
    );
  }
}

class RewardImageAccess {
  const RewardImageAccess(this.uri, {this.headers = const {}});
  final Uri uri;
  final Map<String, String> headers;
}
