import 'package:drift/drift.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/sync/habit_sync_mapping.dart';
import 'package:ruleup/core/sync/supabase_habit_sync_data_source.dart';
import 'package:ruleup/core/sync/sync_transport.dart';
import 'package:ruleup/features/points/domain/point_ledger_source_type.dart';

class SupabaseHabitSyncTransport
    implements
        CursorScopedPullSyncTransport,
        ItemScopedSyncTransport,
        UserScopedPullSyncTransport {
  SupabaseHabitSyncTransport(this._database, this._remote);

  static const phase3CursorKey = 'supabase_habit_pull_cursor';
  final AppDatabase _database;
  final SupabaseHabitSyncDataSource _remote;

  @override
  String get cursorMetadataKey => phase3CursorKey;

  @override
  bool supports(String entityType) =>
      supabaseSyncEntityTypes.contains(entityType);

  @override
  Future<bool> supportsItem(SyncQueueData item) async {
    if (!supports(item.entityType)) return false;
    if (item.entityType != 'point_ledger') return true;
    final entry =
        await (_database.select(_database.pointLedger)..where(
              (row) =>
                  row.id.equals(item.entityId) & row.userId.equals(item.userId),
            ))
            .getSingleOrNull();
    return entry == null || !entry.sourceType.isRedemption;
  }

  @override
  Future<void> send(SyncQueueData item) async {
    if (!supports(item.entityType)) {
      throw SyncTransportException(
        'Supabase financial sync does not support ${item.entityType}.',
      );
    }
    if (_remote.authenticatedUserId != item.userId) {
      throw const HabitSyncException(
        HabitSyncErrorKind.ownership,
        'The queue owner does not match the authenticated Supabase user.',
      );
    }
    var mutation = await HabitSyncMapper.snapshot(_database, item);
    if (mutation.type == HabitSyncEntityType.pointLedger &&
        mutation.row?['source_type'] == 'check_in') {
      final checkInId = mutation.row?['source_id'];
      if (checkInId is! String) {
        throw const HabitSyncException(
          HabitSyncErrorKind.integrity,
          'The check-in ledger source identity is invalid.',
        );
      }
      mutation = await HabitSyncMapper.snapshot(
        _database,
        SyncQueueData(
          id: item.id,
          userId: item.userId,
          entityType: 'check_in',
          entityId: checkInId,
          operation: item.operation,
          attempts: item.attempts,
          createdAt: item.createdAt,
          updatedAt: item.updatedAt,
          lastError: item.lastError,
        ),
      );
    }
    await _remote.push(mutation);
  }

  @override
  Future<PullBatch> pull(String cursor) {
    final userId = _remote.authenticatedUserId;
    if (userId == null) {
      throw const HabitSyncException(
        HabitSyncErrorKind.authentication,
        'An authenticated Supabase session is required.',
      );
    }
    return _remote.pull(cursor, userId: userId);
  }

  @override
  Future<PullBatch> pullForUser(String userId, String cursor) {
    if (_remote.authenticatedUserId != userId) {
      throw const HabitSyncException(
        HabitSyncErrorKind.ownership,
        'The requested pull owner does not match the Supabase session.',
      );
    }
    return _remote.pull(cursor, userId: userId);
  }
}
