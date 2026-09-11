import 'package:drift/drift.dart';
import 'package:ruleup/core/database/database_uuid.dart';
import 'package:ruleup/core/database/tables/local_users.dart';
import 'package:ruleup/core/database/tables/rewards.dart';

class RewardRedemptionRequests extends Table {
  TextColumn get id => text()();
  TextColumn get ledgerId =>
      text().clientDefault(createDatabaseUuid).unique()();
  TextColumn get userId =>
      text().references(LocalUsers, #id, onDelete: KeyAction.cascade)();
  TextColumn get rewardId =>
      text().references(Rewards, #id, onDelete: KeyAction.cascade)();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
