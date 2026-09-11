import 'dart:typed_data';

import 'package:ruleup/core/supabase/supabase_database_service.dart';
import 'package:ruleup/core/sync/habit_sync_mapping.dart';
import 'package:ruleup/core/sync/sync_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class SupabaseHabitSyncDataSource {
  String? get authenticatedUserId;

  Future<void> push(HabitSyncMutation mutation);
  Future<PullBatch> pull(String cursor, {required String userId});
}

abstract interface class SupabaseRewardImageDataSource {
  Future<void> uploadRewardImage(String path, Uint8List bytes, String mimeType);
  Future<void> deleteRewardImage(String path);
}

class SupabaseHabitSyncDataSourceImpl
    implements SupabaseHabitSyncDataSource, SupabaseRewardImageDataSource {
  SupabaseHabitSyncDataSourceImpl(this._database);

  static const _pageSize = 200;
  final SupabaseDatabaseService _database;

  @override
  String? get authenticatedUserId => _database.client.auth.currentUser?.id;

  @override
  Future<void> push(HabitSyncMutation mutation) async {
    final ownerId = _requireOwner(mutation.userId);
    try {
      if (mutation.type == HabitSyncEntityType.checkIn) {
        await _pushCheckIn(mutation, ownerId);
        return;
      }
      if (mutation.type == HabitSyncEntityType.pointLedger) {
        await _pushLedger(mutation, ownerId);
        return;
      }
      if (mutation.type == HabitSyncEntityType.habitReminder &&
          mutation.operation != 'delete') {
        await _pushReminder(mutation, ownerId);
        return;
      }
      if (mutation.operation == 'delete') {
        await _database
            .from(mutation.type.tableName)
            .delete()
            .eq('id', mutation.id)
            .eq('user_id', ownerId);
        return;
      }

      final row = mutation.row;
      if (row == null || row['user_id'] != ownerId) {
        throw const HabitSyncException(
          HabitSyncErrorKind.integrity,
          'The outgoing row owner does not match the authenticated user.',
        );
      }
      final existing = await _database
          .from(mutation.type.tableName)
          .select('user_id,updated_at')
          .eq('id', mutation.id)
          .maybeSingle();
      if (existing != null) {
        if (existing['user_id'] != ownerId) {
          throw const HabitSyncException(
            HabitSyncErrorKind.ownership,
            'The Supabase row belongs to another user.',
          );
        }
        final remoteUpdatedAt = DateTime.parse(existing['updated_at'] as String)
            .toUtc();
        final localUpdatedAt = DateTime.parse(row['updated_at']! as String)
            .toUtc();
        if (!localUpdatedAt.isAfter(remoteUpdatedAt)) return;
      }
      await _database
          .from(mutation.type.tableName)
          .upsert(row, onConflict: 'id');
    } on HabitSyncException {
      rethrow;
    } on PostgrestException catch (error) {
      throw _mapPostgrest(error);
    } on AuthException catch (error) {
      throw HabitSyncException(
        HabitSyncErrorKind.authentication,
        error.message,
      );
    } on Object catch (error) {
      throw HabitSyncException(HabitSyncErrorKind.network, error.toString());
    }
  }

  @override
  Future<PullBatch> pull(String cursor, {required String userId}) async {
    _requireOwner(userId);
    final sequence = int.tryParse(cursor);
    if (sequence == null || sequence < 0) {
      throw const HabitSyncException(
        HabitSyncErrorKind.malformedPayload,
        'The Supabase pull cursor is invalid.',
      );
    }
    try {
      final rawChanges = await _database
          .from('sync_changes')
          .select('sequence,entity_type,entity_id,operation,updated_at,user_id')
          .gt('sequence', sequence)
          .inFilter('entity_type', supabaseSyncEntityTypes.toList())
          .order('sequence')
          .limit(_pageSize);
      final changes = <RemoteChange>[];
      var nextCursor = cursor;
      for (final raw in rawChanges) {
        final change = Map<String, dynamic>.from(raw);
        if (change['user_id'] != userId) {
          throw const HabitSyncException(
            HabitSyncErrorKind.ownership,
            'Supabase exposed another user\'s change record.',
          );
        }
        final changeSequence = change['sequence'];
        if (changeSequence is! num ||
            changeSequence.toInt() != changeSequence) {
          throw const FormatException('Invalid sync change sequence.');
        }
        nextCursor = changeSequence.toInt().toString();
        final type = HabitSyncEntityType.parse(change['entity_type'] as String);
        final entityId = change['entity_id'];
        final operation = change['operation'];
        final updatedAt = DateTime.tryParse(change['updated_at'] as String);
        if (entityId is! String || operation is! String || updatedAt == null) {
          throw const FormatException('Invalid Supabase sync change.');
        }
        if (operation == 'delete') {
          changes.add(
            RemoteChange(
              cursor: nextCursor,
              entityType: type.wireName,
              operation: 'delete',
              updatedAt: updatedAt.toUtc(),
              data: {'id': entityId},
            ),
          );
          continue;
        }
        final remoteRow = await _database
            .from(type.tableName)
            .select()
            .eq('id', entityId)
            .eq('user_id', userId)
            .maybeSingle();
        if (remoteRow == null) {
          // A later hard delete can make an earlier queued upsert snapshot
          // unavailable. Treating it as a tombstone makes replay convergent.
          changes.add(
            RemoteChange(
              cursor: nextCursor,
              entityType: type.wireName,
              operation: 'delete',
              updatedAt: updatedAt.toUtc(),
              data: {'id': entityId},
            ),
          );
          continue;
        }
        changes.add(
          RemoteChange(
            cursor: nextCursor,
            entityType: type.wireName,
            operation: operation,
            updatedAt: updatedAt.toUtc(),
            data: HabitSyncMapper.remoteRowToChangeData(
              type,
              Map<String, dynamic>.from(remoteRow),
              expectedUserId: userId,
            ),
          ),
        );
      }
      return PullBatch(
        changes: changes,
        nextCursor: nextCursor,
        hasMore: rawChanges.length == _pageSize,
      );
    } on HabitSyncException {
      rethrow;
    } on PostgrestException catch (error) {
      throw _mapPostgrest(error);
    } on AuthException catch (error) {
      throw HabitSyncException(
        HabitSyncErrorKind.authentication,
        error.message,
      );
    } on FormatException catch (error) {
      throw HabitSyncException(
        HabitSyncErrorKind.schemaMismatch,
        error.message,
      );
    } on Object catch (error) {
      throw HabitSyncException(HabitSyncErrorKind.network, error.toString());
    }
  }

  Future<void> _pushCheckIn(HabitSyncMutation mutation, String ownerId) async {
    if (mutation.operation == 'delete') {
      throw const HabitSyncException(
        HabitSyncErrorKind.validation,
        'RuleUp does not support deleting check-ins.',
      );
    }
    final row = mutation.row;
    if (row == null || row['user_id'] != ownerId) {
      throw const HabitSyncException(
        HabitSyncErrorKind.integrity,
        'The outgoing check-in owner is invalid.',
      );
    }
    final ledgerId = row['_ledger_id'];
    if (ledgerId is! String) {
      throw const HabitSyncException(
        HabitSyncErrorKind.integrity,
        'The check-in has no stable ledger identity.',
      );
    }
    final checkIn = Map<String, Object?>.from(row)..remove('_ledger_id');
    await _database.rpc(
      'upsert_check_in_with_ledger',
      params: {'p_check_in': checkIn, 'p_ledger_id': ledgerId},
    );
  }

  Future<void> _pushLedger(HabitSyncMutation mutation, String ownerId) async {
    if (mutation.operation == 'delete') {
      throw const HabitSyncException(
        HabitSyncErrorKind.validation,
        'Financial ledger deletion is not supported.',
      );
    }
    final row = mutation.row;
    if (row == null || row['user_id'] != ownerId) {
      throw const HabitSyncException(
        HabitSyncErrorKind.integrity,
        'The outgoing ledger owner is invalid.',
      );
    }
    if (row['source_type'] == 'reward_redemption') {
      final rewardId = row['reward_id'];
      final redemptionId = row['source_id'];
      final ledgerId = row['id'];
      if (rewardId is! String ||
          redemptionId is! String ||
          ledgerId is! String) {
        throw const HabitSyncException(
          HabitSyncErrorKind.integrity,
          'The reward redemption is missing stable identities.',
        );
      }
      await _database.rpc(
        'redeem_reward',
        params: {
          'p_reward_id': rewardId,
          'p_redemption_id': redemptionId,
          'p_ledger_id': ledgerId,
        },
      );
      return;
    }
    if (row['source_type'] != 'missed_check_in') {
      throw const HabitSyncException(
        HabitSyncErrorKind.validation,
        'Only missed penalties have an independent Phase 4 ledger RPC.',
      );
    }
    final sourceId = row['source_id'];
    final ledgerId = row['id'];
    final points = row['points'];
    if (sourceId is! String || ledgerId is! String || points is! int) {
      throw const HabitSyncException(
        HabitSyncErrorKind.malformedPayload,
        'The missed-penalty ledger payload is invalid.',
      );
    }
    final separator = sourceId.lastIndexOf(':');
    if (separator <= 0 || separator == sourceId.length - 1) {
      throw const HabitSyncException(
        HabitSyncErrorKind.malformedPayload,
        'The missed-penalty source identity is invalid.',
      );
    }
    await _database.rpc(
      'record_missed_check_in_penalty',
      params: {
        'p_habit_id': sourceId.substring(0, separator),
        'p_habit_date': sourceId.substring(separator + 1),
        'p_points': points,
        'p_ledger_id': ledgerId,
      },
    );
  }

  Future<void> _pushReminder(HabitSyncMutation mutation, String ownerId) async {
    final row = mutation.row;
    final habitId = row?['habit_id'];
    if (row == null || row['user_id'] != ownerId || habitId is! String) {
      throw const HabitSyncException(
        HabitSyncErrorKind.integrity,
        'The outgoing reminder owner or habit is invalid.',
      );
    }
    final table = _database.from(HabitSyncEntityType.habitReminder.tableName);
    var existing = await table
        .select()
        .eq('user_id', ownerId)
        .eq('habit_id', habitId)
        .maybeSingle();
    if (existing == null) {
      try {
        await table.upsert(row, onConflict: 'id');
        return;
      } on PostgrestException catch (error) {
        if (error.code != '23505') rethrow;
        existing = await table
            .select()
            .eq('user_id', ownerId)
            .eq('habit_id', habitId)
            .maybeSingle();
        if (existing == null) rethrow;
      }
    }

    if (existing['user_id'] != ownerId) {
      throw const HabitSyncException(
        HabitSyncErrorKind.ownership,
        'The Supabase reminder belongs to another user.',
      );
    }
    final remoteUpdatedAt = DateTime.parse(existing['updated_at'] as String)
        .toUtc();
    final localUpdatedAt = DateTime.parse(row['updated_at']! as String).toUtc();
    final canonicalId = existing['id']! as String;
    if (!localUpdatedAt.isAfter(remoteUpdatedAt)) {
      if (canonicalId != mutation.id) {
        // Emit a fresh canonical change so a client whose cursor already
        // passed the original insert can replace its superseded local UUID.
        await table
            .update({'updated_at': existing['updated_at']})
            .eq('id', canonicalId)
            .eq('user_id', ownerId);
      }
      return;
    }
    await table
        .update({
          'enabled': row['enabled'],
          'time_of_day': row['time_of_day'],
          'updated_at': row['updated_at'],
        })
        .eq('id', canonicalId)
        .eq('user_id', ownerId);
  }

  @override
  Future<void> uploadRewardImage(
    String path,
    Uint8List bytes,
    String mimeType,
  ) async {
    try {
      await _database.client.storage
          .from('reward-images')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: true),
          );
    } on StorageException catch (error) {
      throw HabitSyncException(HabitSyncErrorKind.server, error.message);
    } on AuthException catch (error) {
      throw HabitSyncException(
        HabitSyncErrorKind.authentication,
        error.message,
      );
    } on Object catch (error) {
      throw HabitSyncException(HabitSyncErrorKind.network, error.toString());
    }
  }

  @override
  Future<void> deleteRewardImage(String path) async {
    try {
      await _database.client.storage.from('reward-images').remove([path]);
    } on StorageException catch (error) {
      throw HabitSyncException(HabitSyncErrorKind.server, error.message);
    } on AuthException catch (error) {
      throw HabitSyncException(
        HabitSyncErrorKind.authentication,
        error.message,
      );
    } on Object catch (error) {
      throw HabitSyncException(HabitSyncErrorKind.network, error.toString());
    }
  }

  String _requireOwner(String expectedUserId) {
    final current = authenticatedUserId;
    if (current == null) {
      throw const HabitSyncException(
        HabitSyncErrorKind.authentication,
        'An authenticated Supabase session is required.',
      );
    }
    if (current != expectedUserId) {
      throw const HabitSyncException(
        HabitSyncErrorKind.ownership,
        'The local user does not match the authenticated Supabase user.',
      );
    }
    return current;
  }

  HabitSyncException _mapPostgrest(PostgrestException error) {
    final kind = switch (error.code) {
      '42501' => HabitSyncErrorKind.ownership,
      'PGRST301' => HabitSyncErrorKind.authentication,
      '23503' => HabitSyncErrorKind.foreignKeyDependency,
      '22003' ||
      '22023' ||
      'P0001' ||
      '23505' ||
      '23514' ||
      '23P01' => HabitSyncErrorKind.validation,
      '22P02' || 'PGRST204' => HabitSyncErrorKind.schemaMismatch,
      _ => HabitSyncErrorKind.server,
    };
    return HabitSyncException(kind, error.message);
  }
}

enum HabitSyncErrorKind {
  network,
  authentication,
  ownership,
  integrity,
  foreignKeyDependency,
  validation,
  schemaMismatch,
  server,
  malformedPayload,
}

class HabitSyncException implements ClassifiedSyncFailure {
  const HabitSyncException(this.kind, this.message);

  final HabitSyncErrorKind kind;
  final String message;

  @override
  bool get retryable => const {
    HabitSyncErrorKind.network,
    HabitSyncErrorKind.authentication,
    HabitSyncErrorKind.foreignKeyDependency,
    HabitSyncErrorKind.server,
  }.contains(kind);

  @override
  String toString() => '${kind.name}: $message';
}
