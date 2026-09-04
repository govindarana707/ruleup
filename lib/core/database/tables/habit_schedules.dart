import 'package:drift/drift.dart';
import 'package:ruleup/core/database/database_uuid.dart';
import 'package:ruleup/core/database/tables/habits.dart';
import 'package:ruleup/core/database/tables/local_users.dart';

enum ScheduleType { daily, specificDays, timesPerWeek, custom }

class ScheduleTypeConverter extends TypeConverter<ScheduleType, String> {
  const ScheduleTypeConverter();

  @override
  ScheduleType fromSql(String fromDb) => switch (fromDb) {
    'daily' => ScheduleType.daily,
    'specific_days' => ScheduleType.specificDays,
    'times_per_week' => ScheduleType.timesPerWeek,
    'custom' => ScheduleType.custom,
    _ => throw ArgumentError.value(fromDb, 'fromDb', 'Unknown schedule type'),
  };

  @override
  String toSql(ScheduleType value) => switch (value) {
    ScheduleType.daily => 'daily',
    ScheduleType.specificDays => 'specific_days',
    ScheduleType.timesPerWeek => 'times_per_week',
    ScheduleType.custom => 'custom',
  };
}

@TableIndex(
  name: 'habit_schedules_user_habit_idx',
  columns: {#userId, #habitId},
)
class HabitSchedules extends Table {
  TextColumn get id => text().clientDefault(createDatabaseUuid)();
  TextColumn get userId =>
      text().references(LocalUsers, #id, onDelete: KeyAction.cascade)();
  TextColumn get habitId =>
      text().references(Habits, #id, onDelete: KeyAction.cascade)();
  TextColumn get scheduleType => text().map(const ScheduleTypeConverter())();
  TextColumn get scheduleConfig => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
