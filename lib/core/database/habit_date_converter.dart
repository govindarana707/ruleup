import 'package:drift/drift.dart';
import 'package:ruleup/core/utils/habit_date.dart';

class HabitDateConverter extends TypeConverter<DateTime, String> {
  const HabitDateConverter();

  @override
  DateTime fromSql(String fromDb) => parseHabitDate(fromDb);

  @override
  String toSql(DateTime value) => habitDateKey(value);
}
