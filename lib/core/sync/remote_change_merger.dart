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

  Future<String> readCursor(
    String userId, {
    String key = cursorMetadataKey,
  }) async {
    final metadata =
        await (_database.select(_database.syncMetadata)
              ..where((row) => row.userId.equals(userId) & row.key.equals(key)))
            .getSingleOrNull();
    return metadata?.value ?? '0';
  }

  Future<RemoteMergeResult> apply(
    String userId,
    String currentCursor,
    PullBatch batch, {
    String cursorKey = cursorMetadataKey,
  }) => _database.transaction(() async {
    var cursor = currentCursor;
    var merged = 0;
    var blockedByPendingLocalChange = false;
    final reminderHabitIds = <String>{};
    final appliedChanges = <RemoteChange>{};
    var deferred = List<RemoteChange>.of(batch.changes);

    // sync_changes is an event stream, not a relational restore order. A
    // historical check-in can therefore arrive before its habit, option, or
    // matched point rule. Apply parents first and retry deferred children.
    while (deferred.isNotEmpty) {
      var madeProgress = false;
      final retry = <RemoteChange>[];
      for (final change in _dependencyOrdered(deferred)) {
        if (await _hasPendingLocalChange(userId, change)) {
          blockedByPendingLocalChange = true;
          retry.add(change);
          continue;
        }
        if (await _hasMissingDependencies(userId, change)) {
          retry.add(change);
          continue;
        }
        final affectedHabitId = await _reminderHabitId(userId, change);
        if (change.operation == 'delete') {
          await _delete(userId, change);
        } else {
          await _ensureEntityScope(userId, change);
          await _upsert(userId, change);
        }
        if (affectedHabitId != null) reminderHabitIds.add(affectedHabitId);
        appliedChanges.add(change);
        merged++;
        madeProgress = true;
      }
      deferred = retry;
      if (!madeProgress) break;
    }

    // Keep the cursor behind the first unapplied source event. Later parent
    // records may be replayed safely, but no valid child can be skipped.
    for (final change in batch.changes) {
      if (!appliedChanges.contains(change)) break;
      cursor = change.cursor;
    }
    if (deferred.isEmpty) cursor = batch.nextCursor;
    await _writeCursor(userId, cursor, cursorKey);
    return RemoteMergeResult(
      cursor: cursor,
      merged: merged,
      blockedByPendingLocalChange: blockedByPendingLocalChange,
      blockedByDependencies:
          deferred.isNotEmpty && !blockedByPendingLocalChange,
      reminderHabitIds: reminderHabitIds,
      appliedChanges: appliedChanges,
    );
  });

  Iterable<RemoteChange> _dependencyOrdered(List<RemoteChange> changes) {
    final ordered = List<RemoteChange>.of(changes);
    ordered.sort((left, right) {
      final dependency = _dependencyRank(left)
          .compareTo(_dependencyRank(right));
      if (dependency != 0) return dependency;
      return int.parse(left.cursor).compareTo(int.parse(right.cursor));
    });
    return ordered;
  }

  int _dependencyRank(RemoteChange change) {
    final rank = switch (change.entityType) {
      'category' => 0,
      'habit' => 1,
      'habit_option' => 2,
      'habit_schedule' => 3,
      'point_rule' => 4,
      'habit_pause' => 5,
      'habit_reminder' => 6,
      'check_in' => 7,
      'reward' => 8,
      'point_ledger' => 9,
      _ => throw FormatException(
        'Unsupported remote entity type',
        change.entityType,
      ),
    };
    // Tombstones run children first so related remote deletes remain safe.
    return change.operation == 'delete' ? 100 - rank : rank;
  }

  Future<bool> _hasMissingDependencies(
    String userId,
    RemoteChange change,
  ) async {
    if (change.operation == 'delete') return false;
    final data = change.data;
    return switch (change.entityType) {
      'category' || 'reward' => false,
      'habit' => await _missing(
        'categories',
        userId,
        _nullable<String>(data, 'categoryId'),
      ),
      'habit_option' ||
      'habit_schedule' ||
      'point_rule' ||
      'habit_pause' ||
      'habit_reminder' => await _missing(
        'habits',
        userId,
        _required<String>(data, 'habitId'),
      ),
      'check_in' =>
        await _missing('habits', userId, _required<String>(data, 'habitId')) ||
            await _missing(
              'habit_options',
              userId,
              _nullable<String>(data, 'optionId'),
            ) ||
            await _missing(
              'point_rules',
              userId,
              _nullable<String>(data, 'matchedRuleId'),
            ),
      'point_ledger' => await _missing(
        'rewards',
        userId,
        _nullable<String>(data, 'rewardId'),
      ),
      _ => throw FormatException(
        'Unsupported remote entity type',
        change.entityType,
      ),
    };
  }

  Future<bool> _missing(String table, String userId, String? id) async {
    if (id == null) return false;
    final row = await _database
        .customSelect(
          'SELECT 1 FROM $table WHERE id = ? AND user_id = ? LIMIT 1',
          variables: [Variable(id), Variable(userId)],
        )
        .getSingleOrNull();
    return row == null;
  }

  Future<bool> _hasPendingLocalChange(
    String userId,
    RemoteChange change,
  ) async {
    if (change.entityType == 'habit_reminder' && change.operation != 'delete') {
      final habitId = change.data['habitId'];
      if (habitId is String) {
        final localReminder =
            await (_database.select(_database.habitReminders)..where(
                  (row) =>
                      row.userId.equals(userId) & row.habitId.equals(habitId),
                ))
                .getSingleOrNull();
        if (localReminder != null) {
          final pendingCanonicalization =
              await (_database.select(_database.syncQueue)..where(
                    (row) =>
                        row.userId.equals(userId) &
                        row.entityType.equals('habit_reminder') &
                        row.entityId.equals(localReminder.id),
                  ))
                  .getSingleOrNull();
          if (pendingCanonicalization != null) return true;
        }
      }
    }
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
            rewardId: Value(_nullable<String>(data, 'rewardId')),
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
            imageKey: Value(_nullableString(data, 'imageKey')),
            sortOrder: Value(_integer(data, 'sortOrder')),
            createdAt: Value(_date(data, 'createdAt')),
            updatedAt: Value(_date(data, 'updatedAt')),
            archivedAt: Value(_nullableDate(data, 'archivedAt')),
          ),
        );
      case 'habit_reminder':
        final habitId = _required<String>(data, 'habitId');
        await (_database.delete(_database.habitReminders)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.habitId.equals(habitId) &
                  row.id.isNotValue(_id(data)),
            ))
            .go();
        await _database.habitReminders.insertOnConflictUpdate(
          HabitRemindersCompanion.insert(
            id: Value(_id(data)),
            userId: userId,
            habitId: habitId,
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
      case 'check_in':
        await (_database.delete(_database.pointLedger)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.sourceType.equals('check_in') &
                  row.sourceId.equals(id),
            ))
            .go();
        await (_database.delete(
          _database.checkIns,
        )..where((row) => row.id.equals(id) & row.userId.equals(userId))).go();
      case 'point_ledger':
        await (_database.delete(
          _database.pointLedger,
        )..where((row) => row.id.equals(id) & row.userId.equals(userId))).go();
      case 'habit_schedule':
        await (_database.delete(
          _database.habitSchedules,
        )..where((row) => row.id.equals(id) & row.userId.equals(userId))).go();
      case 'habit_pause':
        await (_database.delete(
          _database.habitPauses,
        )..where((row) => row.id.equals(id) & row.userId.equals(userId))).go();
      case 'reward':
        await (_database.delete(
          _database.rewards,
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

  Future<void> _writeCursor(String userId, String cursor, String key) async {
    final now = DateTime.now().toUtc();
    await _database
        .into(_database.syncMetadata)
        .insert(
          SyncMetadataCompanion.insert(
            userId: userId,
            key: key,
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

  String? _nullableString(Map<String, dynamic> data, String key) =>
      _nullable<String>(data, key);

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
    required this.blockedByDependencies,
    required this.reminderHabitIds,
    required this.appliedChanges,
  });

  final String cursor;
  final int merged;
  final bool blockedByPendingLocalChange;
  final bool blockedByDependencies;
  final Set<String> reminderHabitIds;
  final Set<RemoteChange> appliedChanges;
}
