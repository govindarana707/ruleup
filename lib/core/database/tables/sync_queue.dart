import 'package:drift/drift.dart';
import 'package:ruleup/core/database/database_uuid.dart';
import 'package:ruleup/core/database/tables/local_users.dart';

class SyncQueue extends Table {
  TextColumn get id => text().clientDefault(createDatabaseUuid)();

  TextColumn get userId =>
      text().references(LocalUsers, #id, onDelete: KeyAction.cascade)();

  TextColumn get entityType => text()();

  TextColumn get entityId => text()();

  TextColumn get operation => text()();

  IntColumn get attempts => integer().withDefault(const Constant(0))();

  TextColumn get lastError => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {userId, entityType, entityId, operation},
  ];
}
