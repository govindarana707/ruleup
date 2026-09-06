import 'package:drift/drift.dart';
import 'package:ruleup/core/database/database_uuid.dart';
import 'package:ruleup/core/database/habit_date_converter.dart';
import 'package:ruleup/core/database/tables/habits.dart';
import 'package:ruleup/core/database/tables/habit_options.dart';
import 'package:ruleup/core/database/tables/local_users.dart';
import 'package:ruleup/core/database/tables/point_rules.dart';

@TableIndex(name: 'check_ins_user_date_idx', columns: {#userId, #habitDate})
class CheckIns extends Table {
  TextColumn get id => text().clientDefault(createDatabaseUuid)();
  TextColumn get userId =>
      text().references(LocalUsers, #id, onDelete: KeyAction.cascade)();
  TextColumn get habitId =>
      text().references(Habits, #id, onDelete: KeyAction.cascade)();
  TextColumn get habitDate => text().map(const HabitDateConverter())();
  TextColumn get optionId => text().nullable().references(
    HabitOptions,
    #id,
    onDelete: KeyAction.setNull,
  )();
  RealColumn get measuredValue => real().nullable()();
  TextColumn get note => text().nullable()();
  IntColumn get awardedPoints => integer()();
  TextColumn get matchedRuleId =>
      text().nullable().references(PointRules, #id)();
  DateTimeColumn get checkedInAt => dateTime()();
  DateTimeColumn get editableUntil => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {userId, habitId, habitDate},
  ];
}
