import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ruleup/core/network/api_client.dart';
import 'package:ruleup/features/auth/data/token_storage.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/rewards/data/reward_repository.dart';
import 'package:ruleup/features/rewards/data/reward_repository_provider.dart';

final rewardImageServiceProvider = Provider<RewardImageService>(
  (ref) => RewardImageService(
    ref.watch(apiClientProvider),
    ref.watch(tokenStorageProvider),
    ref.watch(rewardRepositoryProvider),
  ),
);

class RewardImageService {
  RewardImageService(this._api, this._tokens, this._rewards);
  final ApiClient _api;
  final TokenStorage _tokens;
  final RewardRepository _rewards;

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
    final token = await _tokens.read();
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
    final response = await _api.postBytes(
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
    final token = await _tokens.read();
    if (token == null) {
      throw const ApiException(
        statusCode: 0,
        code: 'unauthorized',
        message: 'Please sign in again.',
      );
    }
    await _rewards.setImageKey(userId, rewardId, null);
    try {
      await _api.delete(
        '/reward-images/${Uri.encodeComponent(key)}',
        token: token,
      );
    } on Object {
      // The key is removed locally; cleanup can be retried server-side later.
    }
  }
}
