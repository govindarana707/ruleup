import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/database/tables/habit_schedules.dart';
import 'package:ruleup/core/database/tables/habits.dart';
import 'package:ruleup/core/database/tables/point_rules.dart';
import 'package:ruleup/core/sync/sync_transport.dart';
import 'package:ruleup/core/utils/habit_date.dart';

const phase3HabitEntityTypes = <String>{
  'category',
  'habit',
  'habit_option',
  'habit_schedule',
  'point_rule',
  'habit_pause',
  'habit_reminder',
};

enum HabitSyncEntityType {
  category('category', 'categories'),
  habit('habit', 'habits'),
  habitOption('habit_option', 'habit_options'),
  habitSchedule('habit_schedule', 'habit_schedules'),
  pointRule('point_rule', 'point_rules'),
  habitPause('habit_pause', 'habit_pauses'),
  habitReminder('habit_reminder', 'habit_reminders');

  const HabitSyncEntityType(this.wireName, this.tableName);
  final String wireName;
  final String tableName;

  static HabitSyncEntityType parse(String value) => values.firstWhere(
    (type) => type.wireName == value,
    orElse: () => throw FormatException('Unsupported habit entity: $value'),
  );
}

class HabitSyncMutation {
  const HabitSyncMutation({
    required this.type,
    required this.id,
    required this.userId,
    required this.operation,
    required this.row,
  });

  final HabitSyncEntityType type;
  final String id;
  final String userId;
  final String operation;
  final Map<String, Object?>? row;
}

abstract final class HabitSyncMapper {
  static Future<HabitSyncMutation> snapshot(
    AppDatabase database,
    SyncQueueData item,
  ) async {
    final type = HabitSyncEntityType.parse(item.entityType);
    if (item.operation == 'delete') {
      return HabitSyncMutation(
        type: type,
        id: item.entityId,
        userId: item.userId,
        operation: item.operation,
        row: null,
      );
    }
    final row = await _snapshotRow(database, item, type);
    if (row == null) {
      final pendingDelete =
          await (database.select(database.syncQueue)..where(
                (queued) =>
                    queued.userId.equals(item.userId) &
                    queued.entityType.equals(item.entityType) &
                    queued.entityId.equals(item.entityId) &
                    queued.operation.equals('delete'),
              ))
              .getSingleOrNull();
      if (pendingDelete != null) {
        return HabitSyncMutation(
          type: type,
          id: item.entityId,
          userId: item.userId,
          operation: 'delete',
          row: null,
        );
      }
      throw SyncTransportException(
        'The local ${item.entityType} snapshot is no longer available.',
      );
    }
    return HabitSyncMutation(
      type: type,
      id: item.entityId,
      userId: item.userId,
      operation: item.operation,
      row: row,
    );
  }

  static Map<String, dynamic> remoteRowToChangeData(
    HabitSyncEntityType type,
    Map<String, dynamic> row, {
    required String expectedUserId,
  }) {
    if (_string(row, 'user_id') != expectedUserId) {
      throw const SyncIntegrityException(
        'Supabase returned a row owned by another user.',
      );
    }
    final common = <String, dynamic>{
      'id': _string(row, 'id'),
      'createdAt': _timestamp(row, 'created_at'),
      'updatedAt': _timestamp(row, 'updated_at'),
    };
    return switch (type) {
      HabitSyncEntityType.category => {
        ...common,
        'name': _string(row, 'name'),
        'sortOrder': _integer(row, 'sort_order'),
        'archivedAt': _nullableTimestamp(row, 'archived_at'),
      },
      HabitSyncEntityType.habit => {
        ...common,
        'categoryId': _nullableString(row, 'category_id'),
        'name': _string(row, 'name'),
        'measurementType': _string(row, 'measurement_type'),
        'sortOrder': _integer(row, 'sort_order'),
        'missedPenaltyEnabled': _boolean(row, 'missed_penalty_enabled'),
        'missedPenaltyPoints': _integer(row, 'missed_penalty_points'),
        'archivedAt': _nullableTimestamp(row, 'archived_at'),
      },
      HabitSyncEntityType.habitOption => {
        ...common,
        'habitId': _string(row, 'habit_id'),
        'label': _string(row, 'label'),
        'numericValue': _nullableNumber(row, 'numeric_value'),
        'sortOrder': _integer(row, 'sort_order'),
        'archivedAt': _nullableTimestamp(row, 'archived_at'),
      },
      HabitSyncEntityType.habitSchedule => {
        ...common,
        'habitId': _string(row, 'habit_id'),
        'scheduleType': _string(row, 'schedule_type'),
        'scheduleConfig': jsonEncode(_jsonObject(row, 'schedule_config')),
      },
      HabitSyncEntityType.pointRule => {
        ...common,
        'habitId': _string(row, 'habit_id'),
        'operator': _string(row, 'operator'),
        'valueMin': _nullableNumber(row, 'value_min'),
        'valueMax': _nullableNumber(row, 'value_max'),
        'points': _integer(row, 'points'),
        'sortOrder': _integer(row, 'sort_order'),
        'archivedAt': _nullableTimestamp(row, 'archived_at'),
      },
      HabitSyncEntityType.habitPause => {
        ...common,
        'habitId': _string(row, 'habit_id'),
        'startDate': _dateOnly(row, 'start_date'),
        'endDate': _dateOnly(row, 'end_date'),
      },
      HabitSyncEntityType.habitReminder => {
        ...common,
        'habitId': _string(row, 'habit_id'),
        'enabled': _boolean(row, 'enabled'),
        'timeOfDay': _timeOfDay(row, 'time_of_day'),
      },
    };
  }

  static Future<Map<String, Object?>?> _snapshotRow(
    AppDatabase database,
    SyncQueueData item,
    HabitSyncEntityType type,
  ) async {
    return switch (type) {
      HabitSyncEntityType.category => _category(database, item),
      HabitSyncEntityType.habit => _habit(database, item),
      HabitSyncEntityType.habitOption => _option(database, item),
      HabitSyncEntityType.habitSchedule => _schedule(database, item),
      HabitSyncEntityType.pointRule => _rule(database, item),
      HabitSyncEntityType.habitPause => _pause(database, item),
      HabitSyncEntityType.habitReminder => _reminder(database, item),
    };
  }

  static Future<Map<String, Object?>?> _category(
    AppDatabase db,
    SyncQueueData item,
  ) async {
    final row =
        await (db.select(db.categories)..where(
              (r) => r.id.equals(item.entityId) & r.userId.equals(item.userId),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : {
            ..._common(row.id, row.userId, row.createdAt, row.updatedAt),
            'name': row.name,
            'sort_order': row.sortOrder,
            'archived_at': _date(row.archivedAt),
          };
  }

  static Future<Map<String, Object?>?> _habit(
    AppDatabase db,
    SyncQueueData item,
  ) async {
    final row =
        await (db.select(db.habits)..where(
              (r) => r.id.equals(item.entityId) & r.userId.equals(item.userId),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : {
            ..._common(row.id, row.userId, row.createdAt, row.updatedAt),
            'category_id': row.categoryId,
            'name': row.name,
            'measurement_type': const MeasurementTypeConverter().toSql(
              row.measurementType,
            ),
            'sort_order': row.sortOrder,
            'missed_penalty_enabled': row.missedPenaltyEnabled,
            'missed_penalty_points': row.missedPenaltyPoints,
            'archived_at': _date(row.archivedAt),
          };
  }

  static Future<Map<String, Object?>?> _option(
    AppDatabase db,
    SyncQueueData item,
  ) async {
    final row =
        await (db.select(db.habitOptions)..where(
              (r) => r.id.equals(item.entityId) & r.userId.equals(item.userId),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : {
            ..._common(row.id, row.userId, row.createdAt, row.updatedAt),
            'habit_id': row.habitId,
            'label': row.label,
            'numeric_value': row.numericValue,
            'sort_order': row.sortOrder,
            'archived_at': _date(row.archivedAt),
          };
  }

  static Future<Map<String, Object?>?> _schedule(
    AppDatabase db,
    SyncQueueData item,
  ) async {
    final row =
        await (db.select(db.habitSchedules)..where(
              (r) => r.id.equals(item.entityId) & r.userId.equals(item.userId),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : {
            ..._common(row.id, row.userId, row.createdAt, row.updatedAt),
            'habit_id': row.habitId,
            'schedule_type': const ScheduleTypeConverter().toSql(
              row.scheduleType,
            ),
            'schedule_config': _decodeJsonObject(row.scheduleConfig),
          };
  }

  static Future<Map<String, Object?>?> _rule(
    AppDatabase db,
    SyncQueueData item,
  ) async {
    final row =
        await (db.select(db.pointRules)..where(
              (r) => r.id.equals(item.entityId) & r.userId.equals(item.userId),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : {
            ..._common(row.id, row.userId, row.createdAt, row.updatedAt),
            'habit_id': row.habitId,
            'operator': const PointRuleOperatorConverter().toSql(row.operator),
            'value_min': row.valueMin,
            'value_max': row.valueMax,
            'points': row.points,
            'sort_order': row.sortOrder,
            'archived_at': _date(row.archivedAt),
          };
  }

  static Future<Map<String, Object?>?> _pause(
    AppDatabase db,
    SyncQueueData item,
  ) async {
    final row =
        await (db.select(db.habitPauses)..where(
              (r) => r.id.equals(item.entityId) & r.userId.equals(item.userId),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : {
            ..._common(row.id, row.userId, row.createdAt, row.updatedAt),
            'habit_id': row.habitId,
            'start_date': habitDateKey(row.startDate),
            'end_date': habitDateKey(row.endDate),
          };
  }

  static Future<Map<String, Object?>?> _reminder(
    AppDatabase db,
    SyncQueueData item,
  ) async {
    final row =
        await (db.select(db.habitReminders)..where(
              (r) => r.id.equals(item.entityId) & r.userId.equals(item.userId),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : {
            ..._common(row.id, row.userId, row.createdAt, row.updatedAt),
            'habit_id': row.habitId,
            'enabled': row.enabled,
            'time_of_day': row.timeOfDay,
          };
  }

  static Map<String, Object?> _common(
    String id,
    String userId,
    DateTime createdAt,
    DateTime updatedAt,
  ) => {
    'id': id,
    'user_id': userId,
    'created_at': _date(createdAt),
    'updated_at': _date(updatedAt),
  };

  static String? _date(DateTime? value) => value?.toUtc().toIso8601String();

  static Map<String, dynamic> _decodeJsonObject(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('scheduleConfig must be a JSON object.');
    }
    return decoded;
  }

  static String _string(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! String) throw FormatException('Invalid Supabase field: $key');
    return value;
  }

  static String? _nullableString(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value == null) return null;
    if (value is! String) throw FormatException('Invalid Supabase field: $key');
    return value;
  }

  static int _integer(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! num || value.toInt() != value) {
      throw FormatException('Invalid Supabase field: $key');
    }
    return value.toInt();
  }

  static bool _boolean(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! bool) throw FormatException('Invalid Supabase field: $key');
    return value;
  }

  static double? _nullableNumber(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value == null) return null;
    if (value is! num) throw FormatException('Invalid Supabase field: $key');
    return value.toDouble();
  }

  static Map<String, dynamic> _jsonObject(
    Map<String, dynamic> row,
    String key,
  ) {
    final value = row[key];
    if (value is! Map<String, dynamic>) {
      throw FormatException('Invalid Supabase field: $key');
    }
    return value;
  }

  static String _timestamp(Map<String, dynamic> row, String key) {
    final value = _string(row, key);
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw FormatException('Invalid Supabase field: $key');
    return parsed.toUtc().toIso8601String();
  }

  static String? _nullableTimestamp(Map<String, dynamic> row, String key) {
    if (row[key] == null) return null;
    return _timestamp(row, key);
  }

  static String _dateOnly(Map<String, dynamic> row, String key) {
    final value = _string(row, key);
    parseHabitDate(value);
    return value;
  }

  static String _timeOfDay(Map<String, dynamic> row, String key) {
    final value = _string(row, key);
    final match = RegExp(r'^(\d{2}):(\d{2})(?::\d{2}(?:\.\d+)?)?$')
        .firstMatch(value);
    if (match == null) throw FormatException('Invalid Supabase field: $key');
    return '${match.group(1)}:${match.group(2)}';
  }
}

class SyncIntegrityException implements Exception {
  const SyncIntegrityException(this.message);
  final String message;

  @override
  String toString() => message;
}
