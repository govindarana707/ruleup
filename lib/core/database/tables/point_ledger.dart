import 'package:drift/drift.dart';
import 'package:ruleup/core/database/database_uuid.dart';
import 'package:ruleup/core/database/tables/local_users.dart';
import 'package:ruleup/features/points/domain/point_ledger_source_type.dart';

export 'package:ruleup/features/points/domain/point_ledger_source_type.dart';

class PointLedgerSourceTypeConverter
    extends TypeConverter<PointLedgerSourceType, String> {
  const PointLedgerSourceTypeConverter();

  @override
  PointLedgerSourceType fromSql(String fromDb) => switch (fromDb) {
    'check_in' => PointLedgerSourceType.checkIn,
    'missed_check_in' => PointLedgerSourceType.missedCheckIn,
    _ => throw ArgumentError.value(
      fromDb,
      'fromDb',
      'Unknown point ledger source type',
    ),
  };

  @override
  String toSql(PointLedgerSourceType value) => switch (value) {
    PointLedgerSourceType.checkIn => 'check_in',
    PointLedgerSourceType.missedCheckIn => 'missed_check_in',
  };
}

@TableIndex(
  name: 'point_ledger_user_created_idx',
  columns: {#userId, #createdAt},
)
class PointLedger extends Table {
  TextColumn get id => text().clientDefault(createDatabaseUuid)();
  TextColumn get userId =>
      text().references(LocalUsers, #id, onDelete: KeyAction.cascade)();
  TextColumn get sourceType =>
      text().map(const PointLedgerSourceTypeConverter())();
  TextColumn get sourceId => text()();
  IntColumn get points => integer()();
  TextColumn get reason => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {userId, sourceType, sourceId},
  ];
}
