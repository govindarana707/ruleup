import 'package:ruleup/core/database/app_database.dart';

abstract interface class SyncTransport {
  Future<void> send(SyncQueueData item);
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
