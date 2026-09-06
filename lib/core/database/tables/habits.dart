import 'package:drift/drift.dart';
import 'package:ruleup/core/database/database_uuid.dart';
import 'package:ruleup/core/database/tables/categories.dart';
import 'package:ruleup/core/database/tables/local_users.dart';
import 'package:ruleup/features/habits/domain/measurement_type.dart';

export 'package:ruleup/features/habits/domain/measurement_type.dart';

class MeasurementTypeConverter extends TypeConverter<MeasurementType, String> {
  const MeasurementTypeConverter();

  @override
  MeasurementType fromSql(String fromDb) => switch (fromDb) {
    'yes_no' => MeasurementType.yesNo,
    'duration' => MeasurementType.duration,
    'count' => MeasurementType.count,
    'value' => MeasurementType.value,
    _ => throw ArgumentError.value(
      fromDb,
      'fromDb',
      'Unknown measurement type',
    ),
  };

  @override
  String toSql(MeasurementType value) => switch (value) {
    MeasurementType.yesNo => 'yes_no',
    MeasurementType.duration => 'duration',
    MeasurementType.count => 'count',
    MeasurementType.value => 'value',
  };
}

@TableIndex(
  name: 'habits_user_order_idx',
  columns: {#userId, #archivedAt, #sortOrder},
)
@TableIndex(name: 'habits_category_idx', columns: {#categoryId})
class Habits extends Table {
  TextColumn get id => text().clientDefault(createDatabaseUuid)();
  TextColumn get userId =>
      text().references(LocalUsers, #id, onDelete: KeyAction.cascade)();
  TextColumn get categoryId => text().nullable().references(
    Categories,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get name => text()();
  TextColumn get measurementType =>
      text().map(const MeasurementTypeConverter())();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get missedPenaltyEnabled =>
      boolean().withDefault(const Constant(false))();
  IntColumn get missedPenaltyPoints =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get archivedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
