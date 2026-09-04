import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:ruleup/core/database/database_uuid.dart';
import 'package:ruleup/core/database/tables/categories.dart';
import 'package:ruleup/core/database/tables/habits.dart';
import 'package:ruleup/core/database/tables/local_users.dart';
import 'package:ruleup/core/database/tables/sync_metadata.dart';
import 'package:ruleup/core/database/tables/sync_queue.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [LocalUsers, SyncQueue, SyncMetadata, Categories, Habits],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.defaults() : super(driftDatabase(name: 'ruleup'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: _migrate,
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );

  Future<void> _migrate(Migrator migrator, int from, int to) async {
    for (var version = from + 1; version <= to; version++) {
      switch (version) {
        case 1:
          await migrator.createAll();
        case 2:
          await migrator.createTable(categories);
          await migrator.createTable(habits);
          await customStatement(
            'CREATE INDEX categories_user_order_idx '
            'ON categories (user_id, archived_at, sort_order)',
          );
          await customStatement(
            'CREATE INDEX habits_user_order_idx '
            'ON habits (user_id, archived_at, sort_order)',
          );
          await customStatement(
            'CREATE INDEX habits_category_idx ON habits (category_id)',
          );
      }
    }
  }

  Future<int> enqueueSyncOperation(SyncQueueCompanion entry) {
    return into(syncQueue).insert(
      entry,
      onConflict: DoUpdate(
        (_) => SyncQueueCompanion(
          attempts: const Value(0),
          lastError: const Value(null),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
        target: [
          syncQueue.userId,
          syncQueue.entityType,
          syncQueue.entityId,
          syncQueue.operation,
        ],
      ),
    );
  }
}
