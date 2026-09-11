import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/network/api_client.dart';
import 'package:ruleup/core/sync/sync_service.dart';
import 'package:ruleup/core/sync/sync_transport.dart';
import 'package:ruleup/features/auth/data/token_storage.dart';
import 'package:ruleup/features/rewards/data/reward_image_service.dart';
import 'package:ruleup/features/rewards/data/reward_repository.dart';

void main() {
  const userId = '10000000-0000-4000-8000-000000000001';

  test(
    'replacement persists bytes before changing the reward reference',
    () async {
      final directory = await Directory.systemTemp.createTemp('ruleup-image-');
      final file = File(
        '${directory.path}${Platform.pathSeparator}ruleup.sqlite',
      );
      var database = AppDatabase(NativeDatabase(file));
      try {
        await database
            .into(database.localUsers)
            .insert(LocalUsersCompanion.insert(id: const Value(userId)));
        var sync = SyncService(database, const _UnusedTransport());
        var rewards = RewardRepository(database, sync);
        final reward = await rewards.create(
          userId: userId,
          name: 'Picture',
          pointsCost: 10,
        );
        await database.delete(database.syncQueue).go();
        var images = _service(database, sync, rewards);
        final selected = XFile.fromData(
          Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]),
          mimeType: 'image/jpeg',
          name: 'reward.jpg',
        );

        await images.replace(
          userId: userId,
          rewardId: reward.id,
          oldKey: null,
          image: selected,
        );
        final updated = await rewards.getById(userId, reward.id);
        expect(
          updated?.imageKey,
          matches(RegExp('^$userId/${reward.id}/[0-9a-f-]{36}\\.jpg\$')),
        );
        expect(
          (await database.select(database.rewardImageOperations).getSingle())
              .bytes,
          isNotEmpty,
        );
        expect(
          (await database.select(database.syncQueue).get())
              .map((row) => row.entityType)
              .toSet(),
          {'reward_image_upload', 'reward'},
        );
        await database.close();

        database = AppDatabase(NativeDatabase(file));
        sync = SyncService(database, const _UnusedTransport());
        rewards = RewardRepository(database, sync);
        images = _service(database, sync, rewards);
        expect(
          (await database.select(database.rewardImageOperations).getSingle())
              .bytes,
          isNotEmpty,
        );
        expect(await database.select(database.syncQueue).get(), hasLength(2));

        await images.remove(
          userId: userId,
          rewardId: reward.id,
          key: updated!.imageKey!,
        );
        expect((await rewards.getById(userId, reward.id))?.imageKey, isNull);
        expect(
          (await database.select(database.rewardImageOperations).get()).map(
            (row) => row.operation,
          ),
          contains('delete'),
        );
      } finally {
        await database.close();
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      }
    },
  );

  test('rejects unsupported image MIME before queueing', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database
        .into(database.localUsers)
        .insert(LocalUsersCompanion.insert(id: const Value(userId)));
    final sync = SyncService(database, const _UnusedTransport());
    final rewards = RewardRepository(database, sync);
    final reward = await rewards.create(
      userId: userId,
      name: 'Picture',
      pointsCost: 10,
    );
    await database.delete(database.syncQueue).go();

    await expectLater(
      _service(database, sync, rewards).replace(
        userId: userId,
        rewardId: reward.id,
        oldKey: null,
        image: XFile.fromData(
          Uint8List.fromList([1, 2, 3]),
          mimeType: 'image/png',
          name: 'reward.png',
        ),
      ),
      throwsA(isA<ApiException>()),
    );
    expect(
      await database.select(database.rewardImageOperations).get(),
      isEmpty,
    );
  });
}

RewardImageService _service(
  AppDatabase database,
  SyncService sync,
  RewardRepository rewards,
) => RewardImageService(
  ApiClient(
    Uri.parse('https://legacy.invalid'),
    MockClient((_) async => http.Response('{}', 500)),
  ),
  const _TokenStorage(),
  rewards,
  database: database,
  sync: sync,
  supabase: null,
  useSupabase: true,
);

class _TokenStorage implements TokenStorage {
  const _TokenStorage();
  @override
  Future<void> delete() async {}
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String token) async {}
}

class _UnusedTransport implements ScopedSyncTransport {
  const _UnusedTransport();
  @override
  bool supports(String entityType) => false;
  @override
  Future<void> send(SyncQueueData item) => throw UnimplementedError();
}
