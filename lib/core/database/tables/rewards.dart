import 'package:drift/drift.dart';
import 'package:ruleup/core/database/database_uuid.dart';
import 'package:ruleup/core/database/tables/local_users.dart';

@TableIndex(
  name: 'rewards_user_order_idx',
  columns: {#userId, #archivedAt, #sortOrder},
)
class Rewards extends Table {
  TextColumn get id => text().clientDefault(createDatabaseUuid)();
  TextColumn get userId =>
      text().references(LocalUsers, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  IntColumn get pointsCost =>
      integer().check(const CustomExpression<bool>('points_cost > 0'))();
  RealColumn get monetaryCap => real().nullable().check(
    const CustomExpression<bool>('monetary_cap >= 0'),
  )();
  TextColumn get imageKey => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get archivedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
