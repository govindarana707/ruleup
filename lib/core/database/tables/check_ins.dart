import 'package:drift/drift.dart';
import 'package:ruleup/core/database/database_uuid.dart';
import 'package:ruleup/core/database/tables/habits.dart';
import 'package:ruleup/core/database/tables/habit_options.dart';
import 'package:ruleup/core/database/tables/local_users.dart';
import 'package:ruleup/core/database/tables/point_rules.dart';

class HabitDateConverter extends TypeConverter<DateTime, String> {
  const HabitDateConverter();

  @override
  DateTime fromSql(String fromDb) => DateTime.parse('${fromDb}T00:00:00Z');

  @override
  String toSql(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

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
