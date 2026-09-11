import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/sync/habit_sync_mapping.dart';
import 'package:ruleup/core/sync/supabase_habit_sync_data_source.dart';
import 'package:ruleup/core/sync/sync_transport.dart';

class SupabaseHabitSyncTransport
    implements
        CursorScopedPullSyncTransport,
        ScopedSyncTransport,
        UserScopedPullSyncTransport {
  SupabaseHabitSyncTransport(this._database, this._remote);

  static const phase3CursorKey = 'supabase_habit_pull_cursor';
  final AppDatabase _database;
  final SupabaseHabitSyncDataSource _remote;

  @override
  String get cursorMetadataKey => phase3CursorKey;

  @override
  bool supports(String entityType) =>
      phase3HabitEntityTypes.contains(entityType);

  @override
  Future<void> send(SyncQueueData item) async {
    if (!supports(item.entityType)) {
      throw SyncTransportException(
        'Supabase Phase 3 does not support ${item.entityType}.',
      );
    }
    if (_remote.authenticatedUserId != item.userId) {
      throw const HabitSyncException(
        HabitSyncErrorKind.ownership,
        'The queue owner does not match the authenticated Supabase user.',
      );
    }
    await _remote.push(await HabitSyncMapper.snapshot(_database, item));
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
