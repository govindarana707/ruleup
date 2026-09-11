import 'package:drift/drift.dart';
import 'package:ruleup/core/database/database_uuid.dart';
import 'package:ruleup/core/database/tables/local_users.dart';
import 'package:ruleup/core/database/tables/rewards.dart';

class RewardImageOperations extends Table {
  TextColumn get id => text().clientDefault(createDatabaseUuid)();
  TextColumn get userId =>
      text().references(LocalUsers, #id, onDelete: KeyAction.cascade)();
  TextColumn get rewardId =>
      text().references(Rewards, #id, onDelete: KeyAction.cascade)();
  TextColumn get operation => text()();
  TextColumn get objectKey => text()();
  TextColumn get oldObjectKey => text().nullable()();
  BlobColumn get bytes => blob().nullable()();
  TextColumn get mimeType => text().nullable()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
