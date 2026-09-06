import 'package:drift/drift.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/database/tables/habit_schedules.dart';
import 'package:ruleup/core/database/tables/habits.dart';
import 'package:ruleup/core/database/tables/point_ledger.dart';
import 'package:ruleup/core/database/tables/point_rules.dart';
import 'package:ruleup/core/network/api_client.dart';
import 'package:ruleup/core/sync/sync_transport.dart';
import 'package:ruleup/core/utils/habit_date.dart';
import 'package:ruleup/features/auth/data/token_storage.dart';

class ApiSyncTransport implements SyncTransport {
  ApiSyncTransport(this._database, this._api, this._tokens);

  final AppDatabase _database;
  final ApiClient _api;
  final TokenStorage _tokens;

  @override
  Future<void> send(SyncQueueData item) async {
    final token = await _tokens.read();
    if (token == null) {
      throw const SyncTransportException(
        'A valid session is required before syncing.',
      );
    }
    final data = item.operation == 'delete'
        ? <String, Object?>{'id': item.entityId}
        : await _entitySnapshot(item);
    await _api.post(
      '/sync/${item.entityType}',
      token: token,
      body: {'operation': item.operation, 'data': data},
    );
  }

  Future<Map<String, Object?>> _entitySnapshot(SyncQueueData item) async {
    final data = switch (item.entityType) {
      'category' => await _category(item),
      'habit' => await _habit(item),
      'habit_option' => await _habitOption(item),
      'habit_schedule' => await _habitSchedule(item),
      'point_rule' => await _pointRule(item),
      'check_in' => await _checkIn(item),
      'point_ledger' => await _pointLedger(item),
      'habit_pause' => await _habitPause(item),
      'reward' => await _reward(item),
      'habit_reminder' => await _habitReminder(item),
      _ => throw SyncTransportException(
        'Unsupported sync entity type: ${item.entityType}.',
      ),
    };
    if (data == null) {
      throw SyncTransportException(
        'The local ${item.entityType} snapshot is no longer available.',
      );
    }
    return data;
  }

  Future<Map<String, Object?>?> _category(SyncQueueData item) async {
    final row =
        await (_database.select(_database.categories)..where(
              (row) =>
                  row.id.equals(item.entityId) & row.userId.equals(item.userId),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : {
            'id': row.id,
            'name': row.name,
            'sortOrder': row.sortOrder,
            ..._timestamps(row.createdAt, row.updatedAt),
            'archivedAt': _date(row.archivedAt),
          };
  }

  Future<Map<String, Object?>?> _habit(SyncQueueData item) async {
    final row =
        await (_database.select(_database.habits)..where(
              (row) =>
                  row.id.equals(item.entityId) & row.userId.equals(item.userId),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : {
            'id': row.id,
            'categoryId': row.categoryId,
            'name': row.name,
            'measurementType': const MeasurementTypeConverter().toSql(
              row.measurementType,
            ),
            'sortOrder': row.sortOrder,
            'missedPenaltyEnabled': row.missedPenaltyEnabled,
            'missedPenaltyPoints': row.missedPenaltyPoints,
            ..._timestamps(row.createdAt, row.updatedAt),
            'archivedAt': _date(row.archivedAt),
          };
  }

  Future<Map<String, Object?>?> _habitOption(SyncQueueData item) async {
    final row =
        await (_database.select(_database.habitOptions)..where(
              (row) =>
                  row.id.equals(item.entityId) & row.userId.equals(item.userId),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : {
            'id': row.id,
            'habitId': row.habitId,
            'label': row.label,
            'numericValue': row.numericValue,
            'sortOrder': row.sortOrder,
            ..._timestamps(row.createdAt, row.updatedAt),
            'archivedAt': _date(row.archivedAt),
          };
  }

  Future<Map<String, Object?>?> _habitSchedule(SyncQueueData item) async {
    final row =
        await (_database.select(_database.habitSchedules)..where(
              (row) =>
                  row.id.equals(item.entityId) & row.userId.equals(item.userId),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : {
            'id': row.id,
            'habitId': row.habitId,
            'scheduleType': const ScheduleTypeConverter().toSql(
              row.scheduleType,
            ),
            'scheduleConfig': row.scheduleConfig,
            ..._timestamps(row.createdAt, row.updatedAt),
          };
  }

  Future<Map<String, Object?>?> _pointRule(SyncQueueData item) async {
    final row =
        await (_database.select(_database.pointRules)..where(
              (row) =>
                  row.id.equals(item.entityId) & row.userId.equals(item.userId),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : {
            'id': row.id,
            'habitId': row.habitId,
            'operator': const PointRuleOperatorConverter().toSql(row.operator),
            'valueMin': row.valueMin,
            'valueMax': row.valueMax,
            'points': row.points,
            'sortOrder': row.sortOrder,
            ..._timestamps(row.createdAt, row.updatedAt),
            'archivedAt': _date(row.archivedAt),
          };
  }

  Future<Map<String, Object?>?> _checkIn(SyncQueueData item) async {
    final row =
        await (_database.select(_database.checkIns)..where(
              (row) =>
                  row.id.equals(item.entityId) & row.userId.equals(item.userId),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : {
            'id': row.id,
            'habitId': row.habitId,
            'habitDate': habitDateKey(row.habitDate),
            'optionId': row.optionId,
            'measuredValue': row.measuredValue,
            'note': row.note,
            'awardedPoints': row.awardedPoints,
            'matchedRuleId': row.matchedRuleId,
            'checkedInAt': _date(row.checkedInAt),
            'editableUntil': _date(row.editableUntil),
            ..._timestamps(row.createdAt, row.updatedAt),
          };
  }

  Future<Map<String, Object?>?> _pointLedger(SyncQueueData item) async {
    final row =
        await (_database.select(_database.pointLedger)..where(
              (row) =>
                  row.id.equals(item.entityId) & row.userId.equals(item.userId),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : {
            'id': row.id,
            'sourceType': const PointLedgerSourceTypeConverter().toSql(
              row.sourceType,
            ),
            'sourceId': row.sourceId,
            'points': row.points,
            'reason': row.reason,
            'createdAt': _date(row.createdAt),
            // Queue retry bookkeeping changes updatedAt after failures. The
            // immutable createdAt value keeps this queued operation's conflict
            // timestamp stable across retries.
            'updatedAt': _date(item.createdAt),
          };
  }

  Future<Map<String, Object?>?> _habitPause(SyncQueueData item) async {
    final row =
        await (_database.select(_database.habitPauses)..where(
              (row) =>
                  row.id.equals(item.entityId) & row.userId.equals(item.userId),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : {
            'id': row.id,
            'habitId': row.habitId,
            'startDate': habitDateKey(row.startDate),
            'endDate': habitDateKey(row.endDate),
            ..._timestamps(row.createdAt, row.updatedAt),
          };
  }

  Future<Map<String, Object?>?> _reward(SyncQueueData item) async {
    final row =
        await (_database.select(_database.rewards)..where(
              (row) =>
                  row.id.equals(item.entityId) & row.userId.equals(item.userId),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : {
            'id': row.id,
            'name': row.name,
            'pointsCost': row.pointsCost,
            'monetaryCap': row.monetaryCap,
            'sortOrder': row.sortOrder,
            ..._timestamps(row.createdAt, row.updatedAt),
            'archivedAt': _date(row.archivedAt),
          };
  }

  Future<Map<String, Object?>?> _habitReminder(SyncQueueData item) async {
    final row =
        await (_database.select(_database.habitReminders)..where(
              (row) =>
                  row.id.equals(item.entityId) & row.userId.equals(item.userId),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : {
            'id': row.id,
            'habitId': row.habitId,
            'enabled': row.enabled,
            'timeOfDay': row.timeOfDay,
            ..._timestamps(row.createdAt, row.updatedAt),
          };
  }

  Map<String, Object?> _timestamps(DateTime createdAt, DateTime updatedAt) => {
    'createdAt': _date(createdAt),
    'updatedAt': _date(updatedAt),
  };

  String? _date(DateTime? value) => value?.toUtc().toIso8601String();
}

class SyncTransportException implements Exception {
  const SyncTransportException(this.message);

  final String message;

  @override
  String toString() => message;
}
