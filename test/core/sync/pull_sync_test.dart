import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/sync/remote_change_merger.dart';
import 'package:ruleup/core/sync/sync_service.dart';
import 'package:ruleup/core/sync/sync_transport.dart';
import 'package:ruleup/features/habits/domain/measurement_type.dart';
import 'package:ruleup/features/habits/domain/schedule_type.dart';

void main() {
  late AppDatabase database;
  late RemoteChangeMerger merger;
  late _PullTransport transport;
  late SyncService service;
  const userId = '10000000-0000-4000-8000-000000000001';
  const otherUserId = '10000000-0000-4000-8000-000000000002';
  const categoryId = '20000000-0000-4000-8000-000000000001';

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    merger = RemoteChangeMerger(database);
    transport = _PullTransport();
    service = SyncService(database, transport, merger: merger);
    await database
        .into(database.localUsers)
        .insert(LocalUsersCompanion.insert(id: const Value(userId)));
    await database
        .into(database.localUsers)
        .insert(LocalUsersCompanion.insert(id: const Value(otherUserId)));
  });

  tearDown(() => database.close());

  test('initial and incremental pulls update metadata idempotently', () async {
    transport.batches['0'] = PullBatch(
      changes: [_categoryChange('1', categoryId, 'Initial')],
      nextCursor: '1',
      hasMore: false,
    );

    final initial = await service.synchronize(userId);
    expect(initial.pulled, 1);
    expect(
      (await database.select(database.categories).getSingle()).name,
      'Initial',
    );
    expect(await merger.readCursor(userId), '1');

    transport.batches['1'] = PullBatch(
      changes: [_categoryChange('2', categoryId, 'Incremental')],
      nextCursor: '2',
      hasMore: false,
    );
    final incremental = await service.synchronize(userId);
    expect(incremental.pulled, 1);
    expect(
      (await database.select(database.categories).getSingle()).name,
      'Incremental',
    );
    expect(await merger.readCursor(userId), '2');

    final repeated = await service.synchronize(userId);
    expect(repeated.pulled, 0);
    expect(await database.select(database.categories).get(), hasLength(1));
    expect(transport.pullCursors, ['0', '1', '2']);
  });

  test('merges every supported core entity in dependency order', () async {
    const habitId = '30000000-0000-4000-8000-000000000001';
    const optionId = '40000000-0000-4000-8000-000000000001';
    const scheduleId = '50000000-0000-4000-8000-000000000001';
    const ruleId = '60000000-0000-4000-8000-000000000001';
    const checkInId = '70000000-0000-4000-8000-000000000001';
    const ledgerId = '80000000-0000-4000-8000-000000000001';
    const pauseId = '90000000-0000-4000-8000-000000000001';
    const rewardId = 'a0000000-0000-4000-8000-000000000001';
    const reminderId = 'b0000000-0000-4000-8000-000000000001';
    final refreshed = <String>{};
    service = SyncService(
      database,
      transport,
      merger: merger,
      onReminderChanges: (_, habitIds) async => refreshed.addAll(habitIds),
    );
    transport.batches['0'] = PullBatch(
      changes: [
        _categoryChange('1', categoryId, 'Health'),
        _habitChange('2', habitId, categoryId),
        _change('3', 'habit_option', {
          'id': optionId,
          'habitId': habitId,
          'label': 'Ten',
          'numericValue': 10.0,
          'sortOrder': 0,
          ..._remoteTimestamps(3),
          'archivedAt': null,
        }),
        _change('4', 'habit_schedule', {
          'id': scheduleId,
          'habitId': habitId,
          'scheduleType': 'daily',
          'scheduleConfig': '{}',
          ..._remoteTimestamps(4),
        }),
        _change('5', 'point_rule', {
          'id': ruleId,
          'habitId': habitId,
          'operator': 'gte',
          'valueMin': 10.0,
          'valueMax': null,
          'points': 5,
          'sortOrder': 0,
          ..._remoteTimestamps(5),
          'archivedAt': null,
        }),
        _change('6', 'check_in', {
          'id': checkInId,
          'habitId': habitId,
          'habitDate': '2026-01-06',
          'optionId': optionId,
          'measuredValue': 10.0,
          'note': null,
          'awardedPoints': 5,
          'matchedRuleId': ruleId,
          'checkedInAt': '2026-01-06T08:00:00.000Z',
          'editableUntil': '2026-01-07T12:00:00.000Z',
          ..._remoteTimestamps(6),
        }),
        _change('7', 'point_ledger', {
          'id': ledgerId,
          'sourceType': 'check_in',
          'sourceId': checkInId,
          'points': 5,
          'reason': null,
          ..._remoteTimestamps(7),
        }),
        _change('8', 'habit_pause', {
          'id': pauseId,
          'habitId': habitId,
          'startDate': '2026-01-08',
          'endDate': '2026-01-09',
          ..._remoteTimestamps(8),
        }),
        _change('9', 'reward', {
          'id': rewardId,
          'name': 'Movie',
          'pointsCost': 25,
          'monetaryCap': 12.5,
          'sortOrder': 0,
          ..._remoteTimestamps(9),
          'archivedAt': null,
        }),
        _change('10', 'habit_reminder', {
          'id': reminderId,
          'habitId': habitId,
          'enabled': true,
          'timeOfDay': '07:30',
          ..._remoteTimestamps(10),
        }),
      ],
      nextCursor: '10',
      hasMore: false,
    );

    final result = await service.synchronize(userId);

    expect(result.pulled, 10);
    expect(await database.select(database.categories).get(), hasLength(1));
    expect(await database.select(database.habits).get(), hasLength(1));
    expect(await database.select(database.habitOptions).get(), hasLength(1));
    expect(await database.select(database.habitSchedules).get(), hasLength(1));
    expect(await database.select(database.pointRules).get(), hasLength(1));
    expect(await database.select(database.checkIns).get(), hasLength(1));
    expect(await database.select(database.pointLedger).get(), hasLength(1));
    expect(await database.select(database.habitPauses).get(), hasLength(1));
    expect(await database.select(database.rewards).get(), hasLength(1));
    expect(await database.select(database.habitReminders).get(), hasLength(1));
    expect(await merger.readCursor(userId), '10');
    expect(refreshed, {habitId});
  });

  test(
    'server wins without pending work and pending edits are protected',
    () async {
      await _insertCategory(database, userId, categoryId, 'Local newer');
      final serverChange = _categoryChange('1', categoryId, 'Server truth');

      await merger.apply(
        userId,
        '0',
        PullBatch(changes: [serverChange], nextCursor: '1', hasMore: false),
      );
      expect(
        (await database.select(database.categories).getSingle()).name,
        'Server truth',
      );

      await (database.update(database.categories)..where(
            (row) => row.id.equals(categoryId) & row.userId.equals(userId),
          ))
          .write(
            CategoriesCompanion(
              name: const Value('Pending local'),
              updatedAt: Value(DateTime.utc(2027)),
            ),
          );
      await service.enqueue(
        userId: userId,
        entityType: 'category',
        entityId: categoryId,
        operation: 'update',
      );
      final result = await merger.apply(
        userId,
        '1',
        PullBatch(
          changes: [_categoryChange('2', categoryId, 'Must wait')],
          nextCursor: '2',
          hasMore: false,
        ),
      );

      expect(result.blockedByPendingLocalChange, isTrue);
      expect(result.merged, 0);
      expect(
        (await database.select(database.categories).getSingle()).name,
        'Pending local',
      );
      expect(await merger.readCursor(userId), '1');
    },
  );

  test('archive and delete propagation refreshes affected reminders', () async {
    const habitId = '30000000-0000-4000-8000-000000000001';
    const scheduleId = '40000000-0000-4000-8000-000000000001';
    await _insertCategory(database, userId, categoryId, 'Health');
    await _insertHabit(database, userId, habitId, categoryId);
    await database
        .into(database.habitSchedules)
        .insert(
          HabitSchedulesCompanion.insert(
            id: const Value(scheduleId),
            userId: userId,
            habitId: habitId,
            scheduleType: ScheduleType.daily,
            scheduleConfig: '{}',
          ),
        );
    final refreshed = <String>{};
    service = SyncService(
      database,
      transport,
      merger: merger,
      onReminderChanges: (_, habitIds) async => refreshed.addAll(habitIds),
    );
    transport.batches['0'] = PullBatch(
      changes: [
        _habitChange('1', habitId, categoryId, archived: true),
        RemoteChange(
          cursor: '2',
          entityType: 'habit_schedule',
          operation: 'delete',
          updatedAt: DateTime.utc(2026, 1, 2),
          data: const {'id': scheduleId},
        ),
      ],
      nextCursor: '2',
      hasMore: false,
    );

    final result = await service.synchronize(userId);

    expect(result.pulled, 2);
    expect(
      (await database.select(database.habits).getSingle()).archivedAt,
      isNotNull,
    );
    expect(await database.select(database.habitSchedules).get(), isEmpty);
    expect(refreshed, {habitId});
  });

  test('pull merging remains isolated between local users', () async {
    const otherCategoryId = '20000000-0000-4000-8000-000000000002';
    await _insertCategory(database, otherUserId, otherCategoryId, 'Other user');

    await merger.apply(
      userId,
      '0',
      PullBatch(
        changes: [_categoryChange('1', categoryId, 'Current user')],
        nextCursor: '1',
        hasMore: false,
      ),
    );

    final other = await (database.select(
      database.categories,
    )..where((row) => row.userId.equals(otherUserId))).getSingle();
    expect(other.id, otherCategoryId);
    expect(other.name, 'Other user');
    expect(await merger.readCursor(otherUserId), '0');
  });

  test('manual retry sends failed work before pulling', () async {
    await _insertCategory(database, userId, categoryId, 'Local');
    await service.enqueue(
      userId: userId,
      entityType: 'category',
      entityId: categoryId,
      operation: 'update',
    );
    transport.failPush = true;
    transport.batches['0'] = PullBatch(
      changes: [_categoryChange('1', categoryId, 'Remote')],
      nextCursor: '1',
      hasMore: false,
    );

    final first = await service.synchronize(userId);
    expect(first.failed, 1);
    expect(first.pendingProtected, isTrue);
    expect((await database.select(database.syncQueue).getSingle()).attempts, 1);

    transport.failPush = false;
    final retried = await service.synchronize(userId, retryFailures: true);
    expect(retried.succeeded, 1);
    expect(retried.pulled, 1);
    expect(await database.select(database.syncQueue).get(), isEmpty);
    expect(
      (await database.select(database.categories).getSingle()).name,
      'Remote',
    );
  });
}

RemoteChange _categoryChange(String cursor, String id, String name) {
  final updatedAt = DateTime.utc(2026, 1, int.parse(cursor));
  return RemoteChange(
    cursor: cursor,
    entityType: 'category',
    operation: 'upsert',
    updatedAt: updatedAt,
    data: {
      'id': id,
      'name': name,
      'sortOrder': 0,
      'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'archivedAt': null,
    },
  );
}

RemoteChange _change(
  String cursor,
  String entityType,
  Map<String, dynamic> data,
) {
  return RemoteChange(
    cursor: cursor,
    entityType: entityType,
    operation: 'upsert',
    updatedAt: DateTime.utc(2026, 1, int.parse(cursor)),
    data: data,
  );
}

Map<String, dynamic> _remoteTimestamps(int day) => {
  'createdAt': '2026-01-01T00:00:00.000Z',
  'updatedAt': DateTime.utc(2026, 1, day).toIso8601String(),
};

RemoteChange _habitChange(
  String cursor,
  String id,
  String categoryId, {
  bool archived = false,
}) {
  final updatedAt = DateTime.utc(2026, 1, int.parse(cursor));
  return RemoteChange(
    cursor: cursor,
    entityType: 'habit',
    operation: archived ? 'archive' : 'upsert',
    updatedAt: updatedAt,
    data: {
      'id': id,
      'categoryId': categoryId,
      'name': 'Walk',
      'measurementType': 'yes_no',
      'sortOrder': 0,
      'missedPenaltyEnabled': false,
      'missedPenaltyPoints': 0,
      'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'archivedAt': archived ? updatedAt.toIso8601String() : null,
    },
  );
}

Future<void> _insertCategory(
  AppDatabase database,
  String userId,
  String id,
  String name,
) {
  return database
      .into(database.categories)
      .insert(
        CategoriesCompanion.insert(
          id: Value(id),
          userId: userId,
          name: name,
          createdAt: Value(DateTime.utc(2027)),
          updatedAt: Value(DateTime.utc(2027)),
        ),
      );
}

Future<void> _insertHabit(
  AppDatabase database,
  String userId,
  String id,
  String categoryId,
) {
  return database
      .into(database.habits)
      .insert(
        HabitsCompanion.insert(
          id: Value(id),
          userId: userId,
          categoryId: Value(categoryId),
          name: 'Walk',
          measurementType: MeasurementType.yesNo,
        ),
      );
}

class _PullTransport implements PullSyncTransport {
  final Map<String, PullBatch> batches = {};
  final List<String> pullCursors = [];
  bool failPush = false;

  @override
  Future<PullBatch> pull(String cursor) async {
    pullCursors.add(cursor);
    return batches[cursor] ??
        PullBatch(changes: const [], nextCursor: cursor, hasMore: false);
  }

  @override
  Future<void> send(SyncQueueData item) async {
    if (failPush) throw Exception('temporary push failure');
  }
}
