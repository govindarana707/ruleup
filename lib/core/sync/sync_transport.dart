import 'package:ruleup/core/database/app_database.dart';

abstract interface class SyncTransport {
  Future<void> send(SyncQueueData item);
}
