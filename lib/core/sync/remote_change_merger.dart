import 'package:drift/drift.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/database/tables/habit_schedules.dart';
import 'package:ruleup/core/database/tables/habits.dart';
import 'package:ruleup/core/database/tables/point_ledger.dart';
import 'package:ruleup/core/database/tables/point_rules.dart';
import 'package:ruleup/core/sync/sync_transport.dart';
import 'package:ruleup/core/utils/habit_date.dart';

class RemoteChangeMerger {
  RemoteChangeMerger(this._database);

  static const cursorMetadataKey = 'core_pull_cursor';

  final AppDatabase _database;

  Future<String> readCursor(String userId) async {
    final metadata =
        await (_database.select(_database.syncMetadata)..where(
              (row) =>
                  row.userId.equals(userId) & row.key.equals(cursorMetadataKey),
            ))
            .getSingleOrNull();
    return metadata?.value ?? '0';
  }

  Future<RemoteMergeResult> apply(
    String userId,
    String currentCursor,
    PullBatch batch,
  ) => _database.transaction(() async {
    var cursor = currentCursor;
    var merged = 0;
    var blocked = false;
    final reminderHabitIds = <String>{};

    for (final change in batch.changes) {
      if (await _hasPendingLocalChange(userId, change)) {
        blocked = true;
        break;
      }
      final affectedHabitId = await _reminderHabitId(userId, change);
      if (change.operation == 'delete') {
        await _delete(userId, change);
      } else {
        await _ensureEntityScope(userId, change);
        await _upsert(userId, change);
      }
      if (affectedHabitId != null) reminderHabitIds.add(affectedHabitId);
      cursor = change.cursor;
      merged++;
    }

    if (!blocked && batch.changes.isEmpty) cursor = batch.nextCursor;
    await _writeCursor(userId, cursor);
    return RemoteMergeResult(
      cursor: cursor,
      merged: merged,
      blockedByPendingLocalChange: blocked,
      reminderHabitIds: reminderHabitIds,
    );
  });

  Future<bool> _hasPendingLocalChange(
    String userId,
    RemoteChange change,
  ) async {
    final pending =
        await (_database.select(_database.syncQueue)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.entityType.equals(change.entityType) &
                  row.entityId.equals(_id(change.data)),
            ))
            .getSingleOrNull();
    return pending != null;
  }

  Future<void> _ensureEntityScope(String userId, RemoteChange change) async {
    final table = _tableName(change.entityType);
    final existing = await _database
        .customSelect(
          'SELECT user_id FROM $table WHERE id = ?',
          variables: [Variable(_id(change.data))],
        )
        .getSingleOrNull();
    final existingUserId = existing?.read<String>('user_id');
    if (existingUserId != null && existingUserId != userId) {
      throw StateError('Remote entity ID conflicts with another local user.');
    }
  }

  Future<void> _upsert(String userId, RemoteChange change) async {
    final data = change.data;
    switch (change.entityType) {
      case 'category':
        await _database.categories.insertOnConflictUpdate(
          CategoriesCompanion.insert(
            id: Value(_id(data)),
            userId: userId,
            name: _required<String>(data, 'name'),
            sortOrder: Value(_integer(data, 'sortOrder')),
            createdAt: Value(_date(data, 'createdAt')),
            updatedAt: Value(_date(data, 'updatedAt')),
            archivedAt: Value(_nullableDate(data, 'archivedAt')),
          ),
        );
      case 'habit':
        await _database.habits.insertOnConflictUpdate(
          HabitsCompanion.insert(
            id: Value(_id(data)),
            userId: userId,
            categoryId: Value(_nullable<String>(data, 'categoryId')),
            name: _required<String>(data, 'name'),
            measurementType: const MeasurementTypeConverter().fromSql(
              _required<String>(data, 'measurementType'),
            ),
            sortOrder: Value(_integer(data, 'sortOrder')),
            missedPenaltyEnabled: Value(
              _required<bool>(data, 'missedPenaltyEnabled'),
            ),
            missedPenaltyPoints: Value(_integer(data, 'missedPenaltyPoints')),
            createdAt: Value(_date(data, 'createdAt')),
            updatedAt: Value(_date(data, 'updatedAt')),
            archivedAt: Value(_nullableDate(data, 'archivedAt')),
          ),
        );
      case 'habit_option':
        await _database.habitOptions.insertOnConflictUpdate(
          HabitOptionsCompanion.insert(
            id: Value(_id(data)),
            userId: userId,
            habitId: _required<String>(data, 'habitId'),
            label: _required<String>(data, 'label'),
            numericValue: Value(_nullableNumber(data, 'numericValue')),
            sortOrder: Value(_integer(data, 'sortOrder')),
            createdAt: Value(_date(data, 'createdAt')),
            updatedAt: Value(_date(data, 'updatedAt')),
            archivedAt: Value(_nullableDate(data, 'archivedAt')),
          ),
        );
      case 'habit_schedule':
        await _database.habitSchedules.insertOnConflictUpdate(
          HabitSchedulesCompanion.insert(
            id: Value(_id(data)),
            userId: userId,
            habitId: _required<String>(data, 'habitId'),
            scheduleType: const ScheduleTypeConverter().fromSql(
              _required<String>(data, 'scheduleType'),
            ),
            scheduleConfig: _required<String>(data, 'scheduleConfig'),
            createdAt: Value(_date(data, 'createdAt')),
            updatedAt: Value(_date(data, 'updatedAt')),
          ),
        );
      case 'point_rule':
        await _database.pointRules.insertOnConflictUpdate(
          PointRulesCompanion.insert(
            id: Value(_id(data)),
            userId: userId,
            habitId: _required<String>(data, 'habitId'),
            operator: const PointRuleOperatorConverter().fromSql(
              _required<String>(data, 'operator'),
            ),
            valueMin: Value(_nullableNumber(data, 'valueMin')),
            valueMax: Value(_nullableNumber(data, 'valueMax')),
            points: _integer(data, 'points'),
            sortOrder: Value(_integer(data, 'sortOrder')),
            createdAt: Value(_date(data, 'createdAt')),
            updatedAt: Value(_date(data, 'updatedAt')),
            archivedAt: Value(_nullableDate(data, 'archivedAt')),
          ),
        );
      case 'check_in':
        await _database.checkIns.insertOnConflictUpdate(
          CheckInsCompanion.insert(
            id: Value(_id(data)),
            userId: userId,
            habitId: _required<String>(data, 'habitId'),
            habitDate: parseHabitDate(_required<String>(data, 'habitDate')),
            optionId: Value(_nullable<String>(data, 'optionId')),
            measuredValue: Value(_nullableNumber(data, 'measuredValue')),
            note: Value(_nullable<String>(data, 'note')),
            awardedPoints: _integer(data, 'awardedPoints'),
            matchedRuleId: Value(_nullable<String>(data, 'matchedRuleId')),
            checkedInAt: _date(data, 'checkedInAt'),
            editableUntil: _date(data, 'editableUntil'),
            createdAt: Value(_date(data, 'createdAt')),
            updatedAt: Value(_date(data, 'updatedAt')),
          ),
        );
      case 'point_ledger':
        await _database.pointLedger.insertOnConflictUpdate(
          PointLedgerCompanion.insert(
            id: Value(_id(data)),
            userId: userId,
            sourceType: const PointLedgerSourceTypeConverter().fromSql(
              _required<String>(data, 'sourceType'),
            ),
            sourceId: _required<String>(data, 'sourceId'),
            points: _integer(data, 'points'),
            reason: Value(_nullable<String>(data, 'reason')),
            createdAt: Value(_date(data, 'createdAt')),
          ),
        );
      case 'habit_pause':
        await _database.habitPauses.insertOnConflictUpdate(
          HabitPausesCompanion.insert(
            id: Value(_id(data)),
            userId: userId,
            habitId: _required<String>(data, 'habitId'),
            startDate: parseHabitDate(_required<String>(data, 'startDate')),
            endDate: parseHabitDate(_required<String>(data, 'endDate')),
            createdAt: Value(_date(data, 'createdAt')),
            updatedAt: Value(_date(data, 'updatedAt')),
          ),
        );
      case 'reward':
        await _database.rewards.insertOnConflictUpdate(
          RewardsCompanion.insert(
            id: Value(_id(data)),
            userId: userId,
            name: _required<String>(data, 'name'),
            pointsCost: _integer(data, 'pointsCost'),
            monetaryCap: Value(_nullableNumber(data, 'monetaryCap')),
            sortOrder: Value(_integer(data, 'sortOrder')),
            createdAt: Value(_date(data, 'createdAt')),
            updatedAt: Value(_date(data, 'updatedAt')),
            archivedAt: Value(_nullableDate(data, 'archivedAt')),
          ),
        );
      case 'habit_reminder':
        await _database.habitReminders.insertOnConflictUpdate(
          HabitRemindersCompanion.insert(
            id: Value(_id(data)),
            userId: userId,
            habitId: _required<String>(data, 'habitId'),
            enabled: Value(_required<bool>(data, 'enabled')),
            timeOfDay: _required<String>(data, 'timeOfDay'),
            createdAt: Value(_date(data, 'createdAt')),
            updatedAt: Value(_date(data, 'updatedAt')),
          ),
        );
      default:
        throw FormatException(
          'Unsupported remote entity type',
          change.entityType,
        );
    }
  }

  Future<void> _delete(String userId, RemoteChange change) async {
    final id = _id(change.data);
    switch (change.entityType) {
      case 'habit_schedule':
        await (_database.delete(
          _database.habitSchedules,
        )..where((row) => row.id.equals(id) & row.userId.equals(userId))).go();
      case 'habit_pause':
        await (_database.delete(
          _database.habitPauses,
        )..where((row) => row.id.equals(id) & row.userId.equals(userId))).go();
      case 'habit_reminder':
        await (_database.delete(
          _database.habitReminders,
        )..where((row) => row.id.equals(id) & row.userId.equals(userId))).go();
      default:
        throw FormatException(
          'Unsupported remote delete entity type',
          change.entityType,
        );
    }
  }

  Future<String?> _reminderHabitId(String userId, RemoteChange change) async {
    if (change.entityType == 'habit') return _id(change.data);
    if (!const {
      'habit_schedule',
      'habit_pause',
      'habit_reminder',
    }.contains(change.entityType)) {
      return null;
    }
    final remoteHabitId = change.data['habitId'];
    if (remoteHabitId is String) return remoteHabitId;
    final table = _tableName(change.entityType);
    final existing = await _database
        .customSelect(
          'SELECT habit_id FROM $table WHERE id = ? AND user_id = ?',
          variables: [Variable(_id(change.data)), Variable(userId)],
        )
        .getSingleOrNull();
    return existing?.read<String>('habit_id');
  }

  Future<void> _writeCursor(String userId, String cursor) async {
    final now = DateTime.now().toUtc();
    await _database
        .into(_database.syncMetadata)
        .insert(
          SyncMetadataCompanion.insert(
            userId: userId,
            key: cursorMetadataKey,
            value: Value(cursor),
            updatedAt: Value(now),
          ),
          onConflict: DoUpdate(
            (_) => SyncMetadataCompanion(
              value: Value(cursor),
              updatedAt: Value(now),
            ),
            target: [_database.syncMetadata.userId, _database.syncMetadata.key],
          ),
        );
  }

  String _tableName(String entityType) => switch (entityType) {
    'category' => 'categories',
    'habit' => 'habits',
    'habit_option' => 'habit_options',
    'habit_schedule' => 'habit_schedules',
    'point_rule' => 'point_rules',
    'check_in' => 'check_ins',
    'point_ledger' => 'point_ledger',
    'habit_pause' => 'habit_pauses',
    'reward' => 'rewards',
    'habit_reminder' => 'habit_reminders',
    _ => throw FormatException('Unsupported remote entity type', entityType),
  };

  String _id(Map<String, dynamic> data) => _required<String>(data, 'id');

  T _required<T>(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! T) throw FormatException('Invalid remote field: $key');
    return value;
  }

  T? _nullable<T>(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return null;
    if (value is! T) throw FormatException('Invalid remote field: $key');
    return value;
  }

  int _integer(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! num || value.toInt() != value) {
      throw FormatException('Invalid remote field: $key');
    }
    return value.toInt();
  }

  double? _nullableNumber(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return null;
    if (value is! num) throw FormatException('Invalid remote field: $key');
    return value.toDouble();
  }

  DateTime _date(Map<String, dynamic> data, String key) {
    final value = _required<String>(data, key);
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw FormatException('Invalid remote field: $key');
    return parsed.toUtc();
  }

  DateTime? _nullableDate(Map<String, dynamic> data, String key) {
    final value = _nullable<String>(data, key);
    if (value == null) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw FormatException('Invalid remote field: $key');
    return parsed.toUtc();
  }
}

class RemoteMergeResult {
  const RemoteMergeResult({
    required this.cursor,
    required this.merged,
    required this.blockedByPendingLocalChange,
    required this.reminderHabitIds,
  });

  final String cursor;
  final int merged;
  final bool blockedByPendingLocalChange;
  final Set<String> reminderHabitIds;
}
