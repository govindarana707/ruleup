import 'package:ruleup/core/database/app_database.dart';

abstract interface class SyncTransport {
  Future<void> send(SyncQueueData item);
}

abstract interface class ClassifiedSyncFailure implements Exception {
  bool get retryable;
}

class SyncTransportException implements Exception {
  const SyncTransportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Allows a staged transport to leave out-of-scope queue rows untouched.
abstract interface class ScopedSyncTransport implements SyncTransport {
  bool supports(String entityType);
}

/// Gives independent remotes independent durable pull cursors.
abstract interface class CursorScopedPullSyncTransport
    implements PullSyncTransport {
  String get cursorMetadataKey;
}

abstract interface class UserScopedPullSyncTransport
    implements PullSyncTransport {
  Future<PullBatch> pullForUser(String userId, String cursor);
}

abstract interface class PullSyncTransport implements SyncTransport {
  Future<PullBatch> pull(String cursor);
}

class PullBatch {
  const PullBatch({
    required this.changes,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<RemoteChange> changes;
  final String nextCursor;
  final bool hasMore;
}

class RemoteChange {
  const RemoteChange({
    required this.cursor,
    required this.entityType,
    required this.operation,
    required this.updatedAt,
    required this.data,
  });

  final String cursor;
  final String entityType;
  final String operation;
  final DateTime updatedAt;
  final Map<String, dynamic> data;
}
