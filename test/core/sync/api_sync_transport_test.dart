import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/network/api_client.dart';
import 'package:ruleup/core/sync/api_sync_transport.dart';
import 'package:ruleup/core/sync/sync_service.dart';
import 'package:ruleup/features/auth/data/token_storage.dart';
import 'package:ruleup/features/habits/domain/measurement_type.dart';
import 'package:ruleup/features/habits/domain/schedule_type.dart';
import 'package:ruleup/features/points/domain/point_ledger_source_type.dart';
import 'package:ruleup/features/points/domain/point_rule_operator.dart';

void main() {
  late AppDatabase database;
  late _MemoryTokenStorage tokens;
  const userId = '10000000-0000-4000-8000-000000000001';
  const categoryId = '20000000-0000-4000-8000-000000000002';

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    tokens = _MemoryTokenStorage()..token = 'secure-session-token';
    await database
        .into(database.localUsers)
        .insert(LocalUsersCompanion.insert(id: const Value(userId)));
  });

  tearDown(() => database.close());

  test('maps a user-scoped local snapshot without sending userId', () async {
    final now = DateTime.utc(2026, 1, 2, 3, 4, 5);
    await database
        .into(database.categories)
        .insert(
          CategoriesCompanion.insert(
            id: const Value(categoryId),
            userId: userId,
            name: 'Health',
            sortOrder: const Value(3),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    late http.Request captured;
    final transport = ApiSyncTransport(
      database,
      _api((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'data': {
              'entityType': 'category',
              'entityId': categoryId,
              'status': 'created',
            },
          }),
          200,
        );
      }),
      tokens,
    );
    final service = SyncService(database, transport);
    await service.enqueue(
      userId: userId,
      entityType: 'category',
      entityId: categoryId,
      operation: 'create',
    );

    final result = await service.syncPending(userId);
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>;

    expect(result.succeeded, 1);
    expect(captured.url.path, '/sync/category');
    expect(captured.headers['authorization'], 'Bearer secure-session-token');
    expect(body['operation'], 'create');
    expect(data, {
      'id': categoryId,
      'name': 'Health',
      'sortOrder': 3,
      'createdAt': '2026-01-02T03:04:05.000Z',
      'updatedAt': '2026-01-02T03:04:05.000Z',
      'archivedAt': null,
    });
    expect(data, isNot(contains('userId')));
    expect(await database.select(database.syncQueue).get(), isEmpty);
    expect(await database.select(database.categories).getSingle(), isNotNull);
  });

  test('sends id-only delete contracts when the local row is gone', () async {
    late Map<String, dynamic> body;
    final transport = ApiSyncTransport(
      database,
      _api((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"data":{"status":"unchanged"}}', 200);
      }),
      tokens,
    );
    final service = SyncService(database, transport);
    const reminderId = '30000000-0000-4000-8000-000000000003';
    await service.enqueue(
      userId: userId,
      entityType: 'habit_reminder',
      entityId: reminderId,
      operation: 'delete',
    );

    final result = await service.syncPending(userId);

    expect(result.succeeded, 1);
    expect(body, {
      'operation': 'delete',
      'data': {'id': reminderId},
    });
  });

  test('serializes every supported core entity contract', () async {
    final now = DateTime.utc(2026, 2, 3, 4, 5, 6);
    const habitId = '30000000-0000-4000-8000-000000000003';
    const optionId = '40000000-0000-4000-8000-000000000004';
    const scheduleId = '50000000-0000-4000-8000-000000000005';
    const ruleId = '60000000-0000-4000-8000-000000000006';
    const checkInId = '70000000-0000-4000-8000-000000000007';
    const ledgerId = '80000000-0000-4000-8000-000000000008';
    const pauseId = '90000000-0000-4000-8000-000000000009';
    const rewardId = 'a0000000-0000-4000-8000-00000000000a';
    const reminderId = 'b0000000-0000-4000-8000-00000000000b';
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
    await database
        .into(database.habitOptions)
        .insert(
          HabitOptionsCompanion.insert(
            id: const Value(optionId),
            userId: userId,
            habitId: habitId,
            label: 'Ten',
            numericValue: const Value(10),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    await database
        .into(database.habitSchedules)
        .insert(
          HabitSchedulesCompanion.insert(
            id: const Value(scheduleId),
            userId: userId,
            habitId: habitId,
            scheduleType: ScheduleType.specificDays,
            scheduleConfig: '{"days":[1,3,5]}',
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    await database
        .into(database.pointRules)
        .insert(
          PointRulesCompanion.insert(
            id: const Value(ruleId),
            userId: userId,
            habitId: habitId,
            operator: PointRuleOperator.gte,
            valueMin: const Value(10),
            points: 5,
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    await database
        .into(database.checkIns)
        .insert(
          CheckInsCompanion.insert(
            id: const Value(checkInId),
            userId: userId,
            habitId: habitId,
            habitDate: DateTime.utc(2026, 2, 3),
            optionId: const Value(optionId),
            measuredValue: const Value(10),
            awardedPoints: 5,
            matchedRuleId: const Value(ruleId),
            checkedInAt: now,
            editableUntil: now.add(const Duration(hours: 12)),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    await database
        .into(database.pointLedger)
        .insert(
          PointLedgerCompanion.insert(
            id: const Value(ledgerId),
            userId: userId,
            sourceType: PointLedgerSourceType.checkIn,
            sourceId: checkInId,
            points: 5,
            createdAt: Value(now),
          ),
        );
    await database
        .into(database.habitPauses)
        .insert(
          HabitPausesCompanion.insert(
            id: const Value(pauseId),
            userId: userId,
            habitId: habitId,
            startDate: DateTime.utc(2026, 2, 4),
            endDate: DateTime.utc(2026, 2, 5),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    await database
        .into(database.rewards)
        .insert(
          RewardsCompanion.insert(
            id: const Value(rewardId),
            userId: userId,
            name: 'Movie',
            pointsCost: 25,
            monetaryCap: const Value(12.5),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    await database
        .into(database.habitReminders)
        .insert(
          HabitRemindersCompanion.insert(
            id: const Value(reminderId),
            userId: userId,
            habitId: habitId,
            enabled: const Value(true),
            timeOfDay: '07:30',
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );

    final requests = <http.Request>[];
    final transport = ApiSyncTransport(
      database,
      _api((request) async {
        requests.add(request);
        return http.Response('{"data":{"status":"updated"}}', 200);
      }),
      tokens,
    );
    final entities = {
      'category': categoryId,
      'habit': habitId,
      'habit_option': optionId,
      'habit_schedule': scheduleId,
      'point_rule': ruleId,
      'check_in': checkInId,
      'point_ledger': ledgerId,
      'habit_pause': pauseId,
      'reward': rewardId,
      'habit_reminder': reminderId,
    };
    for (final entry in entities.entries) {
      await transport.send(
        SyncQueueData(
          id: 'queue-${entry.key}',
          userId: userId,
          entityType: entry.key,
          entityId: entry.value,
          operation: 'upsert',
          attempts: 0,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    expect(requests.map((request) => request.url.path), [
      for (final entityType in entities.keys) '/sync/$entityType',
    ]);
    for (final request in requests) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>;
      expect(body['operation'], 'upsert');
      expect(data, isNot(contains('userId')));
      expect(data['id'], isNotEmpty);
      expect(data['createdAt'], '2026-02-03T04:05:06.000Z');
      expect(data['updatedAt'], '2026-02-03T04:05:06.000Z');
    }
    final habitBody = jsonDecode(requests[1].body) as Map<String, dynamic>;
    expect(habitBody['data'], containsPair('measurementType', 'count'));
    final scheduleBody = jsonDecode(requests[3].body) as Map<String, dynamic>;
    expect(scheduleBody['data'], containsPair('scheduleType', 'specific_days'));
    final ledgerBody = jsonDecode(requests[6].body) as Map<String, dynamic>;
    expect(ledgerBody['data'], containsPair('sourceType', 'check_in'));
  });

  test(
    'keeps server validation failures retry-safe with useful errors',
    () async {
      final now = DateTime.utc(2026);
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
      final service = SyncService(
        database,
        ApiSyncTransport(
          database,
          _api(
            (_) async => http.Response(
              '{"error":{"code":"validation_error","message":"Invalid category snapshot."}}',
              400,
            ),
          ),
          tokens,
        ),
      );
      await service.enqueue(
        userId: userId,
        entityType: 'category',
        entityId: categoryId,
        operation: 'update',
      );

      final result = await service.syncPending(userId);
      final queued = await database.select(database.syncQueue).getSingle();

      expect(result.failed, 1);
      expect(queued.attempts, 1);
      expect(queued.lastError, 'validation_error: Invalid category snapshot.');
    },
  );

  test('requires a secure session token', () async {
    tokens.token = null;
    final transport = ApiSyncTransport(
      database,
      _api((_) async => http.Response('{}', 200)),
      tokens,
    );
    final item = SyncQueueData(
      id: 'queue-id',
      userId: userId,
      entityType: 'habit_schedule',
      entityId: '40000000-0000-4000-8000-000000000004',
      operation: 'delete',
      attempts: 0,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

    expect(
      () => transport.send(item),
      throwsA(
        isA<SyncTransportException>().having(
          (error) => error.message,
          'message',
          contains('session'),
        ),
      ),
    );
  });
}

ApiClient _api(MockClientHandler handler) =>
    ApiClient(Uri.parse('https://ruleup.test'), MockClient(handler));

class _MemoryTokenStorage implements TokenStorage {
  String? token;

  @override
  Future<void> delete() async => token = null;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String token) async => this.token = token;
}
