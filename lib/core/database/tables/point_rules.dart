import 'package:drift/drift.dart';
import 'package:ruleup/core/database/database_uuid.dart';
import 'package:ruleup/core/database/tables/habits.dart';
import 'package:ruleup/core/database/tables/local_users.dart';

enum PointRuleOperator { completed, eq, lt, lte, gt, gte, between }

class PointRuleOperatorConverter
    extends TypeConverter<PointRuleOperator, String> {
  const PointRuleOperatorConverter();

  @override
  PointRuleOperator fromSql(String fromDb) => switch (fromDb) {
    'completed' => PointRuleOperator.completed,
    'eq' => PointRuleOperator.eq,
    'lt' => PointRuleOperator.lt,
    'lte' => PointRuleOperator.lte,
    'gt' => PointRuleOperator.gt,
    'gte' => PointRuleOperator.gte,
    'between' => PointRuleOperator.between,
    _ => throw ArgumentError.value(
      fromDb,
      'fromDb',
      'Unknown point rule operator',
    ),
  };

  @override
  String toSql(PointRuleOperator value) => switch (value) {
    PointRuleOperator.completed => 'completed',
    PointRuleOperator.eq => 'eq',
    PointRuleOperator.lt => 'lt',
    PointRuleOperator.lte => 'lte',
    PointRuleOperator.gt => 'gt',
    PointRuleOperator.gte => 'gte',
    PointRuleOperator.between => 'between',
  };
}

@TableIndex(
  name: 'point_rules_user_habit_order_idx',
  columns: {#userId, #habitId, #archivedAt, #sortOrder},
)
class PointRules extends Table {
  TextColumn get id => text().clientDefault(createDatabaseUuid)();
  TextColumn get userId =>
      text().references(LocalUsers, #id, onDelete: KeyAction.cascade)();
  TextColumn get habitId =>
      text().references(Habits, #id, onDelete: KeyAction.cascade)();
  TextColumn get operator => text().map(const PointRuleOperatorConverter())();
  RealColumn get valueMin => real().nullable()();
  RealColumn get valueMax => real().nullable()();
  IntColumn get points => integer()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get archivedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
