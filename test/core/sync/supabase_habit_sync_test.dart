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

class _FakeRemote implements SupabaseHabitSyncDataSource {
  _FakeRemote(this.authenticatedUserId);

  @override
  String? authenticatedUserId;
  final List<HabitSyncMutation> pushed = [];
  final List<String> pullUsers = [];
  final Map<String, PullBatch> batches = {};
  bool failPush = false;

  @override
  Future<void> push(HabitSyncMutation mutation) async {
    pushed.add(mutation);
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
}
