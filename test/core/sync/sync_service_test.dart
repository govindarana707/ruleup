import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/sync/sync_service.dart';
import 'package:ruleup/core/sync/sync_transport.dart';

void main() {
  late AppDatabase database;
  late _FakeSyncTransport transport;
  late SyncService service;
  late String userId;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    transport = _FakeSyncTransport();
    service = SyncService(database, transport);
    userId =
        (await database
                .into(database.localUsers)
                .insertReturning(LocalUsersCompanion.insert()))
            .id;
  });

  tearDown(() => database.close());

  test('enqueue adds a user-scoped pending operation', () async {
    await _enqueue(service, userId, 'entity-1');

    final item = await database.select(database.syncQueue).getSingle();
    expect(item.userId, userId);
    expect(item.entityType, 'example_entity');
    expect(item.entityId, 'entity-1');
    expect(item.operation, 'upsert');
    expect(item.attempts, 0);
    expect(item.lastError, isNull);
  });

  test('enqueue deduplicates an equivalent operation', () async {
    await _enqueue(service, userId, 'entity-1');
    final original = await database.select(database.syncQueue).getSingle();
    await _enqueue(service, userId, 'entity-1');

    final items = await database.select(database.syncQueue).get();
    expect(items, hasLength(1));
    expect(items.single.id, original.id);
  });

  test('successful sync removes only the queue item', () async {
    await _enqueue(service, userId, 'entity-1');

    final result = await service.syncPending(userId);

    expect(result.succeeded, 1);
    expect(result.failed, 0);
    expect(await database.select(database.syncQueue).get(), isEmpty);
    expect(
      await (database.select(
        database.localUsers,
      )..where((row) => row.id.equals(userId))).getSingleOrNull(),
      isNotNull,
    );
  });

  test('failure records error and retry attempts the item again', () async {
    await _enqueue(service, userId, 'entity-1');
    transport.shouldFail = true;

    final failed = await service.syncPending(userId);
    final queued = await database.select(database.syncQueue).getSingle();
    expect(failed.failed, 1);
    expect(queued.attempts, 1);
    expect(queued.lastError, contains('transport failed'));

    transport.shouldFail = false;
    final retried = await service.retryFailed(userId);
    expect(retried.succeeded, 1);
    expect(transport.sent, hasLength(2));
    expect(await database.select(database.syncQueue).get(), isEmpty);
  });

  test('sync processes only the requested user queue', () async {
    final otherUserId =
        (await database
                .into(database.localUsers)
                .insertReturning(LocalUsersCompanion.insert()))
            .id;
    await _enqueue(service, userId, 'entity-1');
    await _enqueue(service, otherUserId, 'entity-2');

    await service.syncPending(userId);

    expect(transport.sent.map((item) => item.userId), [userId]);
    final remaining = await database.select(database.syncQueue).getSingle();
    expect(remaining.userId, otherUserId);
  });
}

Future<void> _enqueue(SyncService service, String userId, String entityId) =>
    service.enqueue(
      userId: userId,
      entityType: 'example_entity',
      entityId: entityId,
      operation: 'upsert',
    );

class _FakeSyncTransport implements SyncTransport {
  bool shouldFail = false;
  final List<SyncQueueData> sent = [];

  @override
  Future<void> send(SyncQueueData item) async {
    sent.add(item);
    if (shouldFail) throw Exception('transport failed');
  }
}
