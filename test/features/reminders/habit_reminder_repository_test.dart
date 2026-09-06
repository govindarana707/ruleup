import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/sync/sync_service.dart';
import 'package:ruleup/core/sync/sync_transport.dart';
import 'package:ruleup/features/habits/domain/measurement_type.dart';
import 'package:ruleup/features/reminders/data/habit_reminder_repository.dart';
import 'package:ruleup/features/reminders/domain/habit_reminder_rescheduler.dart';

void main() {
  late AppDatabase database;
  late _RecordingRescheduler rescheduler;
  late HabitReminderRepository reminders;
  late String userId;
  late String otherUserId;
  late String habitId;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    rescheduler = _RecordingRescheduler();
    reminders = HabitReminderRepository(
      database,
      SyncService(database, const _UnusedTransport()),
      rescheduler,
    );
    userId = await _createUser(database);
    otherUserId = await _createUser(database);
    habitId = await _createHabit(database, userId);
  });

  tearDown(() => database.close());

  test(
    'CRUD normalizes time, enables or disables, and enqueues sync',
    () async {
      final created = await reminders.create(
        userId: userId,
        habitId: habitId,
        enabled: true,
        timeOfDay: ' 07:05 ',
      );
      expect(created.enabled, isTrue);
      expect(created.timeOfDay, '07:05');
      expect((await reminders.getForHabit(userId, habitId))?.id, created.id);

      final updated = await reminders.update(
        userId: userId,
        id: created.id,
        enabled: false,
        timeOfDay: '21:30',
      );
      expect(updated?.enabled, isFalse);
      expect(updated?.timeOfDay, '21:30');
      expect(rescheduler.habitIds, [habitId, habitId]);

      expect(await reminders.delete(userId, created.id), isTrue);
      expect(await reminders.getById(userId, created.id), isNull);
      final operations =
          (await (database.select(database.syncQueue)..where(
                    (row) =>
                        row.entityType.equals('habit_reminder') &
                        row.entityId.equals(created.id),
                  ))
                  .get())
              .map((item) => item.operation)
              .toSet();
      expect(operations, {'create', 'update', 'delete'});
    },
  );

  test('validates time and allows only one reminder per habit', () async {
    await expectLater(
      reminders.create(
        userId: userId,
        habitId: habitId,
        enabled: true,
        timeOfDay: '25:00',
      ),
      throwsArgumentError,
    );
    await reminders.create(
      userId: userId,
      habitId: habitId,
      enabled: true,
      timeOfDay: '08:00',
    );
    await expectLater(
      reminders.create(
        userId: userId,
        habitId: habitId,
        enabled: true,
        timeOfDay: '09:00',
      ),
      throwsStateError,
    );
  });

  test('repository enforces user and habit ownership', () async {
    await expectLater(
      reminders.create(
        userId: otherUserId,
        habitId: habitId,
        enabled: true,
        timeOfDay: '08:00',
      ),
      throwsArgumentError,
    );
    final reminder = await reminders.create(
      userId: userId,
      habitId: habitId,
      enabled: true,
      timeOfDay: '08:00',
    );
    expect(await reminders.getById(otherUserId, reminder.id), isNull);
    expect(
      await reminders.update(
        userId: otherUserId,
        id: reminder.id,
        enabled: false,
        timeOfDay: '09:00',
      ),
      isNull,
    );
    expect(await reminders.delete(otherUserId, reminder.id), isFalse);
    expect(await reminders.list(otherUserId), isEmpty);
  });

  test('notification failure never rolls back local reminder writes', () async {
    rescheduler.shouldThrow = true;

    final reminder = await reminders.create(
      userId: userId,
      habitId: habitId,
      enabled: true,
      timeOfDay: '08:00',
    );

    expect(await reminders.getById(userId, reminder.id), isNotNull);
    expect(await database.select(database.syncQueue).get(), hasLength(1));
  });
}

Future<String> _createUser(AppDatabase database) async =>
    (await database
            .into(database.localUsers)
            .insertReturning(LocalUsersCompanion.insert()))
        .id;

Future<String> _createHabit(AppDatabase database, String userId) async =>
    (await database
            .into(database.habits)
            .insertReturning(
              HabitsCompanion.insert(
                userId: userId,
                name: 'Habit',
                measurementType: MeasurementType.yesNo,
              ),
            ))
        .id;

class _RecordingRescheduler implements HabitReminderRescheduler {
  final List<String> habitIds = [];
  bool shouldThrow = false;

  @override
  Future<ReminderScheduleResult> rescheduleHabit(
    String userId,
    String habitId,
  ) async {
    habitIds.add(habitId);
    if (shouldThrow) throw StateError('Notifications unavailable');
    return const ReminderScheduleResult(
      status: ReminderScheduleStatus.scheduled,
    );
  }
}

class _UnusedTransport implements SyncTransport {
  const _UnusedTransport();

  @override
  Future<void> send(SyncQueueData item) => throw UnimplementedError();
}
