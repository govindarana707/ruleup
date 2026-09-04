import 'package:drift/drift.dart';
import 'package:ruleup/core/database/app_database.dart';

abstract interface class LocalUserStore {
  Future<void> ensureExists(String userId);
}

class DriftLocalUserStore implements LocalUserStore {
  DriftLocalUserStore(this._database);

  final AppDatabase _database;

  @override
  Future<void> ensureExists(String userId) async {
    final now = DateTime.now().toUtc();
    await _database
        .into(_database.localUsers)
        .insert(
          LocalUsersCompanion.insert(id: Value(userId), updatedAt: Value(now)),
          onConflict: DoUpdate(
            (_) => LocalUsersCompanion(updatedAt: Value(now)),
          ),
        );
  }
}
