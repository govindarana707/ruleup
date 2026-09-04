import 'package:ruleup/core/database/app_database.dart';

abstract interface class SyncTransport {
  Future<void> send(SyncQueueData item);
}

class DeferredSyncTransport implements SyncTransport {
  const DeferredSyncTransport();

  @override
  Future<void> send(SyncQueueData item) {
    throw UnsupportedError(
      'Entity sync transport is deferred until its backend contract exists.',
    );
  }
}
