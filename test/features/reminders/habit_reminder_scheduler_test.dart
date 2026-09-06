import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/notifications/local_notification_service.dart';
import 'package:ruleup/features/habits/domain/measurement_type.dart';
import 'package:ruleup/features/habits/domain/schedule_type.dart';
import 'package:ruleup/features/reminders/data/habit_reminder_scheduler.dart';
import 'package:ruleup/features/reminders/domain/habit_reminder_rescheduler.dart';

void main() {
  late AppDatabase database;
  late _FakeNotifications notifications;
  late String userId;
  late String habitId;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    notifications = _FakeNotifications();
    userId = await _createUser(database);
    habitId = await _createHabit(database, userId);
  });

  tearDown(() => database.close());

  HabitReminderScheduler scheduler({int horizonDays = 7}) =>
      HabitReminderScheduler(
        database,
        notifications,
        now: () => DateTime(2026, 1, 5, 8),
        horizonDays: horizonDays,
      );

  test('enabled reminder schedules only applicable habit days', () async {
    await _createReminder(database, userId, habitId, timeOfDay: '09:15');
    await database
        .into(database.habitSchedules)
        .insert(
          HabitSchedulesCompanion.insert(
            userId: userId,
            habitId: habitId,
            scheduleType: ScheduleType.specificDays,
            scheduleConfig: '{"days":[1,3,5]}',
          ),
        );

    final result = await scheduler().rescheduleHabit(userId, habitId);

    expect(result.status, ReminderScheduleStatus.scheduled);
    expect(result.scheduledCount, 3);
    expect(notifications.scheduled.map((item) => item.scheduledAt.weekday), [
      DateTime.monday,
      DateTime.wednesday,
      DateTime.friday,
    ]);
    expect(notifications.scheduled.every((item) => item.hour == 9), isTrue);
    expect(notifications.cancelledHabitIds, [habitId]);
  });

  test('disabled reminder cancels and schedules nothing', () async {
    await _createReminder(
      database,
      userId,
      habitId,
      enabled: false,
      timeOfDay: '09:00',
    );

    final result = await scheduler().rescheduleHabit(userId, habitId);

    expect(result.status, ReminderScheduleStatus.inactive);
    expect(notifications.scheduled, isEmpty);
    expect(notifications.permissionRequests, 0);
    expect(notifications.cancelledHabitIds, [habitId]);
  });

  test('paused dates are excluded from scheduling', () async {
    await _createReminder(database, userId, habitId, timeOfDay: '09:00');
    await database
        .into(database.habitPauses)
        .insert(
          HabitPausesCompanion.insert(
            userId: userId,
            habitId: habitId,
            startDate: DateTime(2026, 1, 6),
            endDate: DateTime(2026, 1, 7),
          ),
        );

    final result = await scheduler(horizonDays: 4)
        .rescheduleHabit(userId, habitId);

    expect(result.scheduledCount, 2);
    expect(notifications.scheduled.map((item) => item.scheduledAt.day), [5, 8]);
  });

  test('archived habit cancels and schedules nothing', () async {
    await _createReminder(database, userId, habitId, timeOfDay: '09:00');
    await (database.update(database.habits)
          ..where((row) => row.id.equals(habitId)))
        .write(HabitsCompanion(archivedAt: Value(DateTime.utc(2026, 1, 5))));

    final result = await scheduler().rescheduleHabit(userId, habitId);

    expect(result.status, ReminderScheduleStatus.inactive);
    expect(notifications.scheduled, isEmpty);
    expect(notifications.cancelledHabitIds, [habitId]);
  });

  test('missing permission and service failure are safe results', () async {
    await _createReminder(database, userId, habitId, timeOfDay: '09:00');
    notifications.permissionGranted = false;
    final denied = await scheduler().rescheduleHabit(userId, habitId);
    expect(denied.status, ReminderScheduleStatus.permissionDenied);

    notifications.shouldThrow = true;
    final failed = await scheduler().rescheduleHabit(userId, habitId);
    expect(failed.status, ReminderScheduleStatus.failed);
  });

  test('scheduler remains user scoped', () async {
    final otherUserId = await _createUser(database);
    await _createReminder(database, userId, habitId, timeOfDay: '09:00');

    final result = await scheduler().rescheduleHabit(otherUserId, habitId);

    expect(result.status, ReminderScheduleStatus.inactive);
    expect(notifications.scheduled, isEmpty);
    expect(notifications.cancelledHabitIds, isEmpty);
  });

  test('notification IDs are stable per habit date', () {
    final date = DateTime(2026, 1, 5);
    final first = HabitReminderScheduler.notificationId(habitId, date);
    final repeated = HabitReminderScheduler.notificationId(
      habitId,
      DateTime.utc(2026, 1, 5, 22),
    );
    final anotherDate = HabitReminderScheduler.notificationId(
      habitId,
      DateTime(2026, 1, 6),
    );

    expect(first, repeated);
    expect(first, isNonNegative);
    expect(anotherDate, isNot(first));
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
                name: 'Read',
                measurementType: MeasurementType.yesNo,
              ),
            ))
        .id;

Future<void> _createReminder(
  AppDatabase database,
  String userId,
  String habitId, {
  bool enabled = true,
  required String timeOfDay,
}) async {
  await database
      .into(database.habitReminders)
      .insert(
        HabitRemindersCompanion.insert(
          userId: userId,
          habitId: habitId,
          enabled: Value(enabled),
          timeOfDay: timeOfDay,
        ),
      );
}

class _FakeNotifications implements LocalNotificationService {
  bool permissionGranted = true;
  bool shouldThrow = false;
  int permissionRequests = 0;
  final List<String> cancelledHabitIds = [];
  final List<_ScheduledNotification> scheduled = [];

  @override
  Future<void> initialize() async {
    if (shouldThrow) throw StateError('Unavailable');
  }

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permissionGranted;
  }

  @override
  Future<void> cancelHabit(String habitId) async {
    cancelledHabitIds.add(habitId);
  }

  @override
  Future<void> scheduleHabit({
    required int notificationId,
    required String habitId,
    required String habitName,
    required DateTime scheduledAt,
  }) async {
    scheduled.add(
      _ScheduledNotification(
        id: notificationId,
        habitId: habitId,
        habitName: habitName,
        scheduledAt: scheduledAt,
      ),
    );
  }
}

class _ScheduledNotification {
  const _ScheduledNotification({
    required this.id,
    required this.habitId,
    required this.habitName,
    required this.scheduledAt,
  });

  final int id;
  final String habitId;
  final String habitName;
  final DateTime scheduledAt;
  int get hour => scheduledAt.hour;
}
