import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/database/tables/habits.dart';
import 'package:ruleup/core/database/tables/habit_schedules.dart';
import 'package:ruleup/core/sync/habit_sync_mapping.dart';
import 'package:ruleup/core/sync/supabase_habit_sync_data_source.dart';
import 'package:ruleup/core/sync/supabase_habit_sync_transport.dart';
import 'package:ruleup/core/sync/sync_service.dart';
import 'package:ruleup/core/sync/sync_transport.dart';
import 'package:ruleup/features/categories/data/category_repository.dart';
import 'package:ruleup/features/check_ins/data/check_in_repository.dart';
import 'package:ruleup/features/points/data/point_ledger_repository.dart';
import 'package:ruleup/features/points/domain/point_ledger_source_type.dart';
import 'package:ruleup/features/points/domain/point_rule_operator.dart';
import 'package:ruleup/features/reminders/data/habit_reminder_repository.dart';

void main() {
  late AppDatabase database;
  late _FakeRemote remote;
  late SupabaseHabitSyncTransport transport;
  const userId = '10000000-0000-4000-8000-000000000001';
  const otherUserId = '10000000-0000-4000-8000-000000000002';
  const categoryId = '20000000-0000-4000-8000-000000000001';
  const habitId = '30000000-0000-4000-8000-000000000001';

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database
        .into(database.localUsers)
        .insert(LocalUsersCompanion.insert(id: const Value(userId)));
    remote = _FakeRemote(userId);
    transport = SupabaseHabitSyncTransport(database, remote);
  });

  tearDown(() => database.close());

  test(
    'maps local rows to typed Supabase columns with stable identities',
    () async {
      final now = DateTime.utc(2026, 9, 11, 8, 30);
      await database
          .into(database.categories)
          .insert(
            CategoriesCompanion.insert(
              id: const Value(categoryId),
              userId: userId,
              name: 'Health',
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      await database
          .into(database.habits)
          .insert(
            HabitsCompanion.insert(
              id: const Value(habitId),
              userId: userId,
              categoryId: const Value(categoryId),
              name: 'Walk',
              measurementType: MeasurementType.count,
              missedPenaltyEnabled: const Value(true),
              missedPenaltyPoints: const Value(-2),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      const scheduleId = '40000000-0000-4000-8000-000000000001';
      await database
          .into(database.habitSchedules)
          .insert(
            HabitSchedulesCompanion.insert(
              id: const Value(scheduleId),
              userId: userId,
              habitId: habitId,
              scheduleType: ScheduleType.specificDays,
              scheduleConfig: jsonEncode({
                'weekdays': [1, 3, 5],
              }),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );

      await transport.send(queueItem(userId, 'habit', habitId));
      await transport.send(queueItem(userId, 'habit_schedule', scheduleId));

      final habit = remote.pushed[0].row!;
      expect(habit['id'], habitId);
      expect(habit['user_id'], userId);
      expect(habit['measurement_type'], 'count');
      expect(habit['missed_penalty_enabled'], isTrue);
      expect(habit['missed_penalty_points'], -2);
      final schedule = remote.pushed[1].row!;
      expect(schedule['schedule_type'], 'specific_days');
      expect(schedule['schedule_config'], {
        'weekdays': [1, 3, 5],
      });
    },
  );

  test('normalizes Supabase booleans, nulls, timestamps, JSON and time', () {
    final reminder = HabitSyncMapper.remoteRowToChangeData(
      HabitSyncEntityType.habitReminder,
      {
        ...remoteCommon('50000000-0000-4000-8000-000000000001', userId),
        'habit_id': habitId,
        'enabled': true,
        'time_of_day': '07:30:00',
      },
      expectedUserId: userId,
    );
    expect(reminder['enabled'], isTrue);
    expect(reminder['timeOfDay'], '07:30');
    expect(reminder['createdAt'], '2026-09-11T08:30:00.000Z');

    final schedule = HabitSyncMapper.remoteRowToChangeData(
      HabitSyncEntityType.habitSchedule,
      {
        ...remoteCommon('40000000-0000-4000-8000-000000000001', userId),
        'habit_id': habitId,
        'schedule_type': 'daily',
        'schedule_config': <String, dynamic>{},
      },
      expectedUserId: userId,
    );
    expect(schedule['scheduleConfig'], '{}');

    final option = HabitSyncMapper.remoteRowToChangeData(
      HabitSyncEntityType.habitOption,
      {
        ...remoteCommon('60000000-0000-4000-8000-000000000001', userId),
        'habit_id': habitId,
        'label': 'Ten',
        'numeric_value': null,
        'sort_order': 0,
        'archived_at': null,
      },
      expectedUserId: userId,
    );
    expect(option['numericValue'], isNull);
    expect(option['archivedAt'], isNull);
  });

  test('rejects local and remote ownership injection', () async {
    await database
        .into(database.categories)
        .insert(
          CategoriesCompanion.insert(
            id: const Value(categoryId),
            userId: userId,
            name: 'Private',
          ),
        );
    remote.authenticatedUserId = otherUserId;
    await expectLater(
      transport.send(queueItem(userId, 'category', categoryId)),
      throwsA(
        isA<HabitSyncException>().having(
          (error) => error.kind,
          'kind',
          HabitSyncErrorKind.ownership,
        ),
      ),
    );
    expect(
      () =>
          HabitSyncMapper.remoteRowToChangeData(HabitSyncEntityType.category, {
            ...remoteCommon(categoryId, otherUserId),
            'name': 'Leaked',
            'sort_order': 0,
            'archived_at': null,
          }, expectedUserId: userId),
      throwsA(isA<SyncIntegrityException>()),
    );
  });

  test('delete is idempotent and keeps the stable local entity id', () async {
    final item = queueItem(
      userId,
      'habit_reminder',
      '70000000-0000-4000-8000-000000000001',
      operation: 'delete',
    );
    await transport.send(item);
    await transport.send(item);
    expect(remote.pushed, hasLength(2));
    expect(remote.pushed.every((mutation) => mutation.row == null), isTrue);
    expect(
      remote.pushed.every((mutation) => mutation.id == item.entityId),
      isTrue,
    );
  });

  test('pull is bound to the requested authenticated owner', () async {
    expect(
      () => transport.pullForUser(otherUserId, '0'),
      throwsA(isA<HabitSyncException>()),
    );
    await transport.pullForUser(userId, '0');
    expect(remote.pullUsers, [userId]);
    expect(transport.cursorMetadataKey, 'supabase_habit_pull_cursor');
  });

  test('Supabase pull inserts then updates the same local UUID', () async {
    remote.batches['0'] = PullBatch(
      changes: [remoteCategoryChange('1', categoryId, 'First')],
      nextCursor: '1',
      hasMore: false,
    );
    final service = SyncService(database, transport);
    expect((await service.synchronize(userId)).pulled, 1);
    expect(
      (await database.select(database.categories).getSingle()).name,
      'First',
    );

    remote.batches['1'] = PullBatch(
      changes: [remoteCategoryChange('2', categoryId, 'Updated')],
      nextCursor: '2',
      hasMore: false,
    );
    expect((await service.synchronize(userId)).pulled, 1);
    expect(
      (await database.select(database.categories).getSingle()).name,
      'Updated',
    );
    expect(await database.select(database.categories).get(), hasLength(1));
    final cursor =
        await (database.select(database.syncMetadata)..where(
              (row) =>
                  row.key.equals(SupabaseHabitSyncTransport.phase3CursorKey),
            ))
            .getSingle();
    expect(cursor.value, '2');
  });

  test('offline local write and queue survive restart then retry', () async {
    await database.close();
    final directory = await Directory.systemTemp.createTemp('ruleup-phase3-');
    final file = File(
      '${directory.path}${Platform.pathSeparator}ruleup.sqlite',
    );
    try {
      var persistentDatabase = AppDatabase(NativeDatabase(file));
      await persistentDatabase
          .into(persistentDatabase.localUsers)
          .insert(LocalUsersCompanion.insert(id: const Value(userId)));
      var persistentRemote = _FakeRemote(userId)..failPush = true;
      var persistentTransport = SupabaseHabitSyncTransport(
        persistentDatabase,
        persistentRemote,
      );
      var service = SyncService(persistentDatabase, persistentTransport);
      final repository = CategoryRepository(persistentDatabase, service);

      final category = await repository.create(
        userId: userId,
        name: 'Works offline',
      );
      expect(category.name, 'Works offline');
      expect(
        await persistentDatabase.select(persistentDatabase.syncQueue).get(),
        hasLength(1),
      );
      final failed = await service.syncPending(userId);
      expect(failed.failed, 1);
      await persistentDatabase.close();

      persistentDatabase = AppDatabase(NativeDatabase(file));
      persistentRemote = _FakeRemote(userId);
      persistentTransport = SupabaseHabitSyncTransport(
        persistentDatabase,
        persistentRemote,
      );
      service = SyncService(persistentDatabase, persistentTransport);
      expect(
        await persistentDatabase.select(persistentDatabase.categories).get(),
        hasLength(1),
      );
      expect(
        await persistentDatabase.select(persistentDatabase.syncQueue).get(),
        hasLength(1),
      );

      final retried = await service.retryFailed(userId);
      expect(retried.succeeded, 1);
      expect(persistentRemote.pushed.single.id, category.id);
      expect(
        await persistentDatabase.select(persistentDatabase.syncQueue).get(),
        isEmpty,
      );
      await persistentDatabase.close();
    } finally {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    }
  });

  test('offline reminder and dependency survive restart then retry', () async {
    await database.close();
    final directory = await Directory.systemTemp.createTemp('ruleup-phase6-');
    final file = File(
      '${directory.path}${Platform.pathSeparator}ruleup.sqlite',
    );
    try {
      var persistentDatabase = AppDatabase(NativeDatabase(file));
      await persistentDatabase
          .into(persistentDatabase.localUsers)
          .insert(LocalUsersCompanion.insert(id: const Value(userId)));
      await persistentDatabase
          .into(persistentDatabase.habits)
          .insert(
            HabitsCompanion.insert(
              id: const Value(habitId),
              userId: userId,
              name: 'Remember me',
              measurementType: MeasurementType.yesNo,
            ),
          );
      var persistentRemote = _FakeRemote(userId)..failPush = true;
      var service = SyncService(
        persistentDatabase,
        SupabaseHabitSyncTransport(persistentDatabase, persistentRemote),
      );
      await service.enqueue(
        userId: userId,
        entityType: 'habit',
        entityId: habitId,
        operation: 'create',
      );
      final reminder =
          await HabitReminderRepository(persistentDatabase, service).create(
            userId: userId,
            habitId: habitId,
            enabled: true,
            timeOfDay: '07:45',
          );
      expect((await service.syncPending(userId)).failed, 2);
      await persistentDatabase.close();

      persistentDatabase = AppDatabase(NativeDatabase(file));
      persistentRemote = _FakeRemote(userId);
      service = SyncService(
        persistentDatabase,
        SupabaseHabitSyncTransport(persistentDatabase, persistentRemote),
      );
      expect(
        (await persistentDatabase
                .select(persistentDatabase.habitReminders)
                .getSingle())
            .id,
        reminder.id,
      );
      expect((await service.retryFailed(userId)).succeeded, 2);
      expect(
        persistentRemote.pushed.map((mutation) => mutation.type).toList(),
        [HabitSyncEntityType.habit, HabitSyncEntityType.habitReminder],
      );
      expect(
        await persistentDatabase.select(persistentDatabase.syncQueue).get(),
        isEmpty,
      );
      await persistentDatabase.close();
    } finally {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    }
  });

  test(
    'check-in and ledger queue replay through one atomic RPC shape',
    () async {
      await database
          .into(database.habits)
          .insert(
            HabitsCompanion.insert(
              id: const Value(habitId),
              userId: userId,
              name: 'Walk',
              measurementType: MeasurementType.yesNo,
            ),
          );
      const ruleId = '40000000-0000-4000-8000-000000000001';
      await database
          .into(database.pointRules)
          .insert(
            PointRulesCompanion.insert(
              id: const Value(ruleId),
              userId: userId,
              habitId: habitId,
              operator: PointRuleOperator.completed,
              points: 10,
            ),
          );
      final service = SyncService(database, transport);
      final checkIn =
          await CheckInRepository(
            database,
            service,
            now: () => DateTime.utc(2026, 9, 11, 8),
          ).create(
            userId: userId,
            habitId: habitId,
            habitDate: DateTime.utc(2026, 9, 11),
          );
      final ledger = await PointLedgerRepository(
        database,
        service,
      ).getForCheckIn(userId, checkIn.id);

      expect(await database.select(database.syncQueue).get(), hasLength(2));
      final result = await service.syncPending(userId);

      expect(result.succeeded, 2);
      expect(await database.select(database.syncQueue).get(), isEmpty);
      expect(remote.pushed, hasLength(2));
      expect(
        remote.pushed.every(
          (mutation) => mutation.type == HabitSyncEntityType.checkIn,
        ),
        isTrue,
      );
      expect(remote.pushed.map((mutation) => mutation.id).toSet(), {
        checkIn.id,
      });
      expect(
        remote.pushed.map((mutation) => mutation.row?['_ledger_id']).toSet(),
        {ledger!.id},
      );
    },
  );

  test(
    'offline financial transaction and outbox survive process restart',
    () async {
      await database.close();
      final directory = await Directory.systemTemp.createTemp('ruleup-phase4-');
      final file = File(
        '${directory.path}${Platform.pathSeparator}ruleup.sqlite',
      );
      try {
        var persistentDatabase = AppDatabase(NativeDatabase(file));
        await persistentDatabase
            .into(persistentDatabase.localUsers)
            .insert(LocalUsersCompanion.insert(id: const Value(userId)));
        await persistentDatabase
            .into(persistentDatabase.habits)
            .insert(
              HabitsCompanion.insert(
                id: const Value(habitId),
                userId: userId,
                name: 'Offline walk',
                measurementType: MeasurementType.yesNo,
              ),
            );
        await persistentDatabase
            .into(persistentDatabase.pointRules)
            .insert(
              PointRulesCompanion.insert(
                userId: userId,
                habitId: habitId,
                operator: PointRuleOperator.completed,
                points: 10,
              ),
            );
        var persistentRemote = _FakeRemote(userId)..failPush = true;
        var service = SyncService(
          persistentDatabase,
          SupabaseHabitSyncTransport(persistentDatabase, persistentRemote),
        );
        final checkIn =
            await CheckInRepository(
              persistentDatabase,
              service,
              now: () => DateTime.utc(2026, 9, 11, 8),
            ).create(
              userId: userId,
              habitId: habitId,
              habitDate: DateTime.utc(2026, 9, 11),
            );
        final wallet = await PointLedgerRepository(
          persistentDatabase,
          service,
        ).getWallet(userId);
        expect(wallet.availablePoints, 10);
        expect((await service.syncPending(userId)).failed, 2);
        await persistentDatabase.close();

        persistentDatabase = AppDatabase(NativeDatabase(file));
        persistentRemote = _FakeRemote(userId);
        service = SyncService(
          persistentDatabase,
          SupabaseHabitSyncTransport(persistentDatabase, persistentRemote),
        );
        expect(
          (await persistentDatabase
                  .select(persistentDatabase.checkIns)
                  .getSingle())
              .id,
          checkIn.id,
        );
        expect(
          await persistentDatabase.select(persistentDatabase.syncQueue).get(),
          hasLength(2),
        );
        expect((await service.retryFailed(userId)).succeeded, 2);
        expect(
          persistentRemote.pushed.every(
            (mutation) =>
                mutation.type == HabitSyncEntityType.checkIn &&
                mutation.id == checkIn.id,
          ),
          isTrue,
        );
        expect(
          await persistentDatabase.select(persistentDatabase.syncQueue).get(),
          isEmpty,
        );
        await persistentDatabase.close();
      } finally {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      }
    },
  );

  test(
    'missed penalty and deferred redemption use their trusted RPC shapes',
    () async {
      await database
          .into(database.habits)
          .insert(
            HabitsCompanion.insert(
              id: const Value(habitId),
              userId: userId,
              name: 'Walk',
              measurementType: MeasurementType.yesNo,
            ),
          );
      final service = SyncService(database, transport);
      final ledger = PointLedgerRepository(database, service);
      final missed = await ledger.createMissedCheckInPenalty(
        userId: userId,
        habitId: habitId,
        habitDate: DateTime.utc(2026, 9, 10),
        points: -5,
      );
      const redemptionId = '50000000-0000-4000-8000-000000000001';
      const rewardId = '60000000-0000-4000-8000-000000000001';
      await database
          .into(database.rewards)
          .insert(
            RewardsCompanion.insert(
              id: const Value(rewardId),
              userId: userId,
              name: 'Deferred',
              pointsCost: 10,
            ),
          );
      await database
          .into(database.pointLedger)
          .insert(
            PointLedgerCompanion.insert(
              id: const Value(redemptionId),
              userId: userId,
              sourceType: PointLedgerSourceType.rewardRedemption,
              sourceId: '70000000-0000-4000-8000-000000000001',
              points: -10,
              reason: const Value('Reward: Deferred'),
            ),
          );
      await service.enqueue(
        userId: userId,
        entityType: 'point_ledger',
        entityId: redemptionId,
        operation: 'create',
      );

      final result = await service.syncPending(userId);

      expect(result.succeeded, 2);
      expect(remote.pushed, hasLength(2));
      final missedMutation = remote.pushed.singleWhere(
        (mutation) => mutation.row?['source_type'] == 'missed_check_in',
      );
      final redemptionMutation = remote.pushed.singleWhere(
        (mutation) => mutation.row?['source_type'] == 'reward_redemption',
      );
      expect(missedMutation.id, missed.id);
      expect(redemptionMutation.id, redemptionId);
      expect(redemptionMutation.row?['reward_id'], rewardId);
      expect(await database.select(database.syncQueue).get(), isEmpty);
    },
  );

  test('reward image upload is durable, owner-bound, and idempotent', () async {
    const rewardId = '60000000-0000-4000-8000-000000000001';
    const operationId = '70000000-0000-4000-8000-000000000001';
    const objectId = '80000000-0000-4000-8000-000000000001';
    final objectKey = '$userId/$rewardId/$objectId.jpg';
    await database
        .into(database.rewards)
        .insert(
          RewardsCompanion.insert(
            id: const Value(rewardId),
            userId: userId,
            name: 'Photo reward',
            pointsCost: 10,
          ),
        );
    await database
        .into(database.rewardImageOperations)
        .insert(
          RewardImageOperationsCompanion.insert(
            id: const Value(operationId),
            userId: userId,
            rewardId: rewardId,
            operation: 'upload',
            objectKey: objectKey,
            bytes: Value(Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9])),
            mimeType: const Value('image/jpeg'),
          ),
        );
    final item = queueItem(userId, 'reward_image_upload', operationId);

    await transport.send(item);
    await transport.send(item);

    expect(remote.uploadedImages, [objectKey]);
    final operation = await database
        .select(database.rewardImageOperations)
        .getSingle();
    expect(operation.completed, isTrue);
    expect(operation.bytes, isNull);

    const invalidOperationId = '90000000-0000-4000-8000-000000000001';
    await database
        .into(database.rewardImageOperations)
        .insert(
          RewardImageOperationsCompanion.insert(
            id: const Value(invalidOperationId),
            userId: userId,
            rewardId: rewardId,
            operation: 'delete',
            objectKey: '$otherUserId/$rewardId/$objectId.jpg',
          ),
        );
    await expectLater(
      transport.send(
        queueItem(userId, 'reward_image_delete', invalidOperationId),
      ),
      throwsA(
        isA<SyncIntegrityException>().having(
          (error) => error.retryable,
          'retryable',
          isFalse,
        ),
      ),
    );
  });

  test(
    'reward replacement pushes upload, reference, then old deletion',
    () async {
      const rewardId = '60000000-0000-4000-8000-000000000001';
      const uploadId = '70000000-0000-4000-8000-000000000001';
      const deleteId = '80000000-0000-4000-8000-000000000001';
      const newObject = '90000000-0000-4000-8000-000000000001';
      const oldObject = 'a0000000-0000-4000-8000-000000000001';
      final newKey = '$userId/$rewardId/$newObject.webp';
      final oldKey = '$userId/$rewardId/$oldObject.jpg';
      await database
          .into(database.rewards)
          .insert(
            RewardsCompanion.insert(
              id: const Value(rewardId),
              userId: userId,
              name: 'Replacement',
              pointsCost: 10,
              imageKey: Value(newKey),
            ),
          );
      await database
          .into(database.rewardImageOperations)
          .insert(
            RewardImageOperationsCompanion.insert(
              id: const Value(uploadId),
              userId: userId,
              rewardId: rewardId,
              operation: 'upload',
              objectKey: newKey,
              bytes: Value(Uint8List.fromList([1, 2, 3])),
              mimeType: const Value('image/webp'),
            ),
          );
      await database
          .into(database.rewardImageOperations)
          .insert(
            RewardImageOperationsCompanion.insert(
              id: const Value(deleteId),
              userId: userId,
              rewardId: rewardId,
              operation: 'delete',
              objectKey: oldKey,
            ),
          );
      final service = SyncService(database, transport);
      await service.enqueue(
        userId: userId,
        entityType: 'reward_image_delete',
        entityId: deleteId,
        operation: 'delete',
      );
      await service.enqueue(
        userId: userId,
        entityType: 'reward',
        entityId: rewardId,
        operation: 'update',
      );
      await service.enqueue(
        userId: userId,
        entityType: 'reward_image_upload',
        entityId: uploadId,
        operation: 'upload',
      );

      expect((await service.syncPending(userId)).succeeded, 3);
      expect(remote.events, [
        'upload:$newKey',
        'push:reward',
        'delete:$oldKey',
      ]);
      expect(remote.pushed.single.row?['image_key'], newKey);
    },
  );
}

SyncQueueData queueItem(
  String userId,
  String entityType,
  String entityId, {
  String operation = 'create',
}) => SyncQueueData(
  id: 'queue-$entityId-$operation',
  userId: userId,
  entityType: entityType,
  entityId: entityId,
  operation: operation,
  attempts: 0,
  createdAt: DateTime.utc(2026, 9, 11),
  updatedAt: DateTime.utc(2026, 9, 11),
);

Map<String, dynamic> remoteCommon(String id, String owner) => {
  'id': id,
  'user_id': owner,
  'created_at': '2026-09-11T08:30:00+00:00',
  'updated_at': '2026-09-11T08:30:00+00:00',
};

RemoteChange remoteCategoryChange(String cursor, String id, String name) =>
    RemoteChange(
      cursor: cursor,
      entityType: 'category',
      operation: 'upsert',
      updatedAt: DateTime.utc(2026, 9, 11, 8, int.parse(cursor)),
      data: {
        'id': id,
        'name': name,
        'sortOrder': 0,
        'createdAt': '2026-09-11T08:00:00.000Z',
        'updatedAt': '2026-09-11T08:0$cursor:00.000Z',
        'archivedAt': null,
      },
    );

class _FakeRemote
    implements SupabaseHabitSyncDataSource, SupabaseRewardImageDataSource {
  _FakeRemote(this.authenticatedUserId);

  @override
  String? authenticatedUserId;
  final List<HabitSyncMutation> pushed = [];
  final List<String> pullUsers = [];
  final Map<String, PullBatch> batches = {};
  bool failPush = false;
  final List<String> uploadedImages = [];
  final List<String> deletedImages = [];
  final List<String> events = [];

  @override
  Future<void> push(HabitSyncMutation mutation) async {
    pushed.add(mutation);
    events.add('push:${mutation.type.wireName}');
    if (failPush) {
      throw const HabitSyncException(HabitSyncErrorKind.network, 'offline');
    }
  }

  @override
  Future<PullBatch> pull(String cursor, {required String userId}) async {
    pullUsers.add(userId);
    return batches[cursor] ??
        PullBatch(changes: const [], nextCursor: cursor, hasMore: false);
  }

  @override
  Future<void> uploadRewardImage(
    String path,
    Uint8List bytes,
    String mimeType,
  ) async {
    uploadedImages.add(path);
    events.add('upload:$path');
  }

  @override
  Future<void> deleteRewardImage(String path) async {
    deletedImages.add(path);
    events.add('delete:$path');
  }
}
