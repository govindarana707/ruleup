import 'package:drift/drift.dart';
import 'package:ruleup/core/database/database_uuid.dart';
import 'package:ruleup/core/database/tables/habits.dart';
import 'package:ruleup/core/database/tables/local_users.dart';

@TableIndex(
  name: 'habit_reminders_user_habit_idx',
  columns: {#userId, #habitId},
  unique: true,
)
class HabitReminders extends Table {
  TextColumn get id => text().clientDefault(createDatabaseUuid)();
  TextColumn get userId =>
      text().references(LocalUsers, #id, onDelete: KeyAction.cascade)();
  TextColumn get habitId =>
      text().references(Habits, #id, onDelete: KeyAction.cascade)();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  TextColumn get timeOfDay => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
