import 'package:drift/drift.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/sync/habit_sync_mapping.dart';
import 'package:ruleup/core/sync/supabase_habit_sync_data_source.dart';
import 'package:ruleup/core/sync/sync_transport.dart';

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
      supabaseSyncEntityTypes.contains(entityType) ||
      const {
        'reward_redemption',
        'reward_image_upload',
        'reward_image_delete',
      }.contains(entityType);

  @override
  Future<bool> supportsItem(SyncQueueData item) async {
    if (!supports(item.entityType)) return false;
    return true;
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
    if (item.entityType == 'reward_redemption') {
      await _sendRedemptionRequest(item);
      return;
    }
    if (item.entityType == 'reward_image_upload' ||
        item.entityType == 'reward_image_delete') {
      await _sendRewardImage(item);
      return;
    }
    var mutation = await HabitSyncMapper.snapshot(_database, item);
    if (mutation.type == HabitSyncEntityType.pointLedger &&
        mutation.row?['source_type'] == 'reward_redemption' &&
        mutation.row?['reward_id'] == null) {
      mutation = await _resolveLegacyRedemption(mutation, item);
    }
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

  Future<void> _sendRewardImage(SyncQueueData item) async {
    final operation =
        await (_database.select(_database.rewardImageOperations)..where(
              (row) =>
                  row.id.equals(item.entityId) & row.userId.equals(item.userId),
            ))
            .getSingleOrNull();
    if (operation == null) {
      throw const SyncIntegrityException(
        'The durable reward image operation is missing.',
      );
    }
    if (operation.completed) return;
    final ownerPrefix = '${operation.userId}/${operation.rewardId}/';
    if (!operation.objectKey.startsWith(ownerPrefix)) {
      throw const SyncIntegrityException(
        'The reward image path does not match its owner and reward.',
      );
    }
    if (_remote is! SupabaseRewardImageDataSource) {
      throw const SyncTransportException(
        'The Supabase transport has no reward image storage boundary.',
      );
    }
    final storage = _remote as SupabaseRewardImageDataSource;
    if (operation.operation == 'upload') {
      final bytes = operation.bytes;
      final mimeType = operation.mimeType;
      if (bytes == null ||
          bytes.isEmpty ||
          bytes.length > 1024 * 1024 ||
          !const {'image/jpeg', 'image/webp'}.contains(mimeType)) {
        throw const SyncIntegrityException(
          'The queued reward image payload is invalid.',
        );
      }
      await storage.uploadRewardImage(operation.objectKey, bytes, mimeType!);
    } else if (operation.operation == 'delete') {
      await storage.deleteRewardImage(operation.objectKey);
    } else {
      throw const SyncIntegrityException(
        'The queued reward image operation is invalid.',
      );
    }
    await (_database.update(
      _database.rewardImageOperations,
    )..where((row) => row.id.equals(operation.id))).write(
      RewardImageOperationsCompanion(
        bytes: const Value(null),
        completed: const Value(true),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> _sendRedemptionRequest(SyncQueueData item) async {
    final request =
        await (_database.select(_database.rewardRedemptionRequests)..where(
              (row) =>
                  row.id.equals(item.entityId) & row.userId.equals(item.userId),
            ))
            .getSingleOrNull();
    if (request == null) {
      throw const SyncIntegrityException(
        'The durable redemption request is missing.',
      );
    }
    if (request.status == 'completed') return;
    await _remote.push(
      HabitSyncMutation(
        type: HabitSyncEntityType.pointLedger,
        id: request.ledgerId,
        userId: request.userId,
        operation: 'create',
        row: {
          'id': request.ledgerId,
          'user_id': request.userId,
          'source_type': 'reward_redemption',
          'source_id': request.id,
          'reward_id': request.rewardId,
        },
      ),
    );
    await (_database.update(_database.rewardRedemptionRequests)..where(
          (row) =>
              row.id.equals(request.id) & row.userId.equals(request.userId),
        ))
        .write(
          RewardRedemptionRequestsCompanion(
            status: const Value('completed'),
            lastError: const Value(null),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
  }

  Future<HabitSyncMutation> _resolveLegacyRedemption(
    HabitSyncMutation mutation,
    SyncQueueData item,
  ) async {
    final points = mutation.row?['points'];
    final reason = mutation.row?['reason'];
    if (points is! int || points >= 0 || reason is! String) {
      throw const SyncIntegrityException(
        'The deferred reward redemption payload is invalid.',
      );
    }
    const prefix = 'Reward: ';
    final name = reason.startsWith(prefix)
        ? reason.substring(prefix.length)
        : null;
    if (name == null || name.isEmpty) {
      throw const SyncIntegrityException(
        'The deferred redemption cannot identify its reward.',
      );
    }
    final matches =
        await (_database.select(_database.rewards)..where(
              (reward) =>
                  reward.userId.equals(item.userId) &
                  reward.name.equals(name) &
                  reward.pointsCost.equals(-points),
            ))
            .get();
    if (matches.isEmpty) {
      throw const HabitSyncException(
        HabitSyncErrorKind.foreignKeyDependency,
        'The reward required by the deferred redemption is not available yet.',
      );
    }
    if (matches.length != 1) {
      throw const SyncIntegrityException(
        'The deferred redemption matches more than one local reward.',
      );
    }
    final rewardId = matches.single.id;
    await (_database.update(_database.pointLedger)..where(
          (entry) =>
              entry.id.equals(item.entityId) & entry.userId.equals(item.userId),
        ))
        .write(PointLedgerCompanion(rewardId: Value(rewardId)));
    final row = Map<String, Object?>.from(mutation.row!)
      ..['reward_id'] = rewardId;
    return HabitSyncMutation(
      type: mutation.type,
      id: mutation.id,
      userId: mutation.userId,
      operation: mutation.operation,
      row: row,
    );
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
