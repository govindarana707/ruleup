import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/database/tables/habit_schedules.dart';
import 'package:ruleup/core/database/tables/habits.dart';
import 'package:ruleup/core/sync/sync_service.dart';
import 'package:ruleup/core/sync/sync_transport.dart';
import 'package:ruleup/features/habits/data/habit_option_repository.dart';
import 'package:ruleup/features/habits/data/habit_schedule_repository.dart';

void main() {
  late AppDatabase database;
  late HabitOptionRepository options;
  late HabitScheduleRepository schedules;
  late String userId;
  late String otherUserId;
  late String habitId;
  late String otherHabitId;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final sync = SyncService(database, const _UnusedTransport());
    options = HabitOptionRepository(database, sync);
    schedules = HabitScheduleRepository(database, sync);
    userId = await _createUser(database);
    otherUserId = await _createUser(database);
    habitId = await _createHabit(database, userId, 'Primary');
    otherHabitId = await _createHabit(database, otherUserId, 'Other');
  });

  tearDown(() => database.close());

  test('habit option CRUD stores values and enqueues sync', () async {
    final created = await options.create(
      userId: userId,
      habitId: habitId,
      label: ' 30 minutes ',
      numericValue: 30,
      sortOrder: 2,
    );
    expect(created.label, '30 minutes');
    expect(created.numericValue, 30);

    final updated = await options.update(
      userId: userId,
      id: created.id,
      habitId: habitId,
      label: '45 minutes',
      numericValue: 45.5,
      sortOrder: 1,
    );
    expect(updated?.label, '45 minutes');
    expect((await options.getById(userId, created.id))?.numericValue, 45.5);

    final queue = await database.select(database.syncQueue).get();
    expect(queue.map((item) => item.entityType).toSet(), {'habit_option'});
    expect(queue.map((item) => item.operation).toSet(), {'create', 'update'});
  });

  test('habit options are ordered and archived instead of deleted', () async {
    final later = await options.create(
      userId: userId,
      habitId: habitId,
      label: 'Later',
      sortOrder: 2,
    );
    final first = await options.create(
      userId: userId,
      habitId: habitId,
      label: 'First',
      sortOrder: 1,
    );

    expect(
      (await options.listForHabit(userId, habitId)).map((item) => item.id),
      [first.id, later.id],
    );
    expect(await options.archive(userId, first.id), isTrue);
    expect(await options.listForHabit(userId, habitId), hasLength(1));
    expect(
      await options.listForHabit(userId, habitId, includeArchived: true),
      hasLength(2),
    );
    expect((await options.getById(userId, first.id))?.archivedAt, isNotNull);

    final archive =
        await (database.select(database.syncQueue)..where(
              (row) =>
                  row.entityId.equals(first.id) &
                  row.operation.equals('archive'),
            ))
            .getSingle();
    expect(archive.userId, userId);
  });

  test('habit schedule CRUD stores supported type and enqueues sync', () async {
    final created = await schedules.create(
      userId: userId,
      habitId: habitId,
      scheduleType: ScheduleType.specificDays,
      scheduleConfig: ' {"days":[1,3,5]} ',
    );
    expect(created.scheduleConfig, '{"days":[1,3,5]}');

    final stored = await database
        .customSelect(
          'SELECT schedule_type FROM habit_schedules WHERE id = ?',
          variables: [Variable(created.id)],
        )
        .getSingle();
    expect(stored.read<String>('schedule_type'), 'specific_days');

    final updated = await schedules.update(
      userId: userId,
      id: created.id,
      habitId: habitId,
      scheduleType: ScheduleType.timesPerWeek,
      scheduleConfig: '{"times":4}',
    );
    expect(updated?.scheduleType, ScheduleType.timesPerWeek);
    expect(await schedules.listForHabit(userId, habitId), hasLength(1));
    expect(await schedules.delete(userId, created.id), isTrue);
    expect(await schedules.getById(userId, created.id), isNull);

    final queue = await database.select(database.syncQueue).get();
    expect(queue.map((item) => item.entityType).toSet(), {'habit_schedule'});
    expect(queue.map((item) => item.operation).toSet(), {
      'create',
      'update',
      'delete',
    });
  });

  test('repositories isolate users and enforce habit ownership', () async {
    final option = await options.create(
      userId: userId,
      habitId: habitId,
      label: 'Private option',
    );
    final schedule = await schedules.create(
      userId: userId,
      habitId: habitId,
      scheduleType: ScheduleType.daily,
      scheduleConfig: '{}',
    );

    expect(await options.getById(otherUserId, option.id), isNull);
    expect(await options.archive(otherUserId, option.id), isFalse);
    expect(await schedules.getById(otherUserId, schedule.id), isNull);
    expect(await schedules.delete(otherUserId, schedule.id), isFalse);
    expect(await options.listForHabit(otherUserId, habitId), isEmpty);
    expect(await schedules.listForHabit(otherUserId, habitId), isEmpty);

    await expectLater(
      options.create(userId: userId, habitId: otherHabitId, label: 'Invalid'),
      throwsArgumentError,
    );
    await expectLater(
      schedules.create(
        userId: userId,
        habitId: otherHabitId,
        scheduleType: ScheduleType.custom,
        scheduleConfig: '{}',
      ),
      throwsArgumentError,
    );
  });
}

Future<String> _createUser(AppDatabase database) async =>
    (await database
            .into(database.localUsers)
            .insertReturning(LocalUsersCompanion.insert()))
        .id;

Future<String> _createHabit(
  AppDatabase database,
  String userId,
  String name,
) async =>
    (await database
            .into(database.habits)
            .insertReturning(
              HabitsCompanion.insert(
                userId: userId,
                name: name,
                measurementType: MeasurementType.yesNo,
              ),
            ))
        .id;

class _UnusedTransport implements SyncTransport {
  const _UnusedTransport();

  @override
  Future<void> send(SyncQueueData item) => throw UnimplementedError();
}
