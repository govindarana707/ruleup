import 'package:drift/drift.dart';
import 'package:ruleup/core/database/database_uuid.dart';

class LocalUsers extends Table {
  TextColumn get id => text().clientDefault(createDatabaseUuid)();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
