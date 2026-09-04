import 'package:drift/drift.dart';
import 'package:ruleup/core/database/database_uuid.dart';
import 'package:ruleup/core/database/tables/local_users.dart';

@TableIndex(
  name: 'categories_user_order_idx',
  columns: {#userId, #archivedAt, #sortOrder},
)
class Categories extends Table {
  TextColumn get id => text().clientDefault(createDatabaseUuid)();
  TextColumn get userId =>
      text().references(LocalUsers, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get archivedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
