import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/core/database/app_database.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test('initializes the version 4 local schema', () async {
    final tables = await database
        .customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'table' AND name IN "
          "('local_users', 'sync_queue', 'sync_metadata', "
          "'categories', 'habits', 'habit_options', 'habit_schedules', "
          "'point_rules')",
        )
        .get();

    expect(database.schemaVersion, 4);
    expect(tables.map((row) => row.read<String>('name')).toSet(), {
      'local_users',
      'sync_queue',
      'sync_metadata',
      'categories',
      'habits',
      'habit_options',
      'habit_schedules',
      'point_rules',
    });
  });

  test('deduplicates equivalent pending sync operations', () async {
    final user = await database
        .into(database.localUsers)
        .insertReturning(LocalUsersCompanion.insert());

    SyncQueueCompanion entry() => SyncQueueCompanion.insert(
      userId: user.id,
      entityType: 'example_entity',
      entityId: '7c4f4502-0a56-4a23-a423-e7d9154be269',
      operation: 'upsert',
    );

    await database.enqueueSyncOperation(entry());
    final original = await database.select(database.syncQueue).getSingle();
    await database.enqueueSyncOperation(entry());
    final queued = await database.select(database.syncQueue).get();

    expect(queued, hasLength(1));
    expect(queued.single.id, original.id);
  });

  test('migrates a version 1 database through the latest schema', () async {
    await database.close();
    final upgraded = AppDatabase(
      NativeDatabase.memory(
        setup: (rawDatabase) {
          rawDatabase.execute(
            'CREATE TABLE local_users ('
            'id TEXT NOT NULL PRIMARY KEY, '
            'created_at INTEGER NOT NULL, '
            'updated_at INTEGER NOT NULL)',
          );
          rawDatabase.userVersion = 1;
        },
      ),
    );
    addTearDown(upgraded.close);

    final entities = await upgraded
        .customSelect(
          "SELECT name FROM sqlite_master WHERE name IN "
          "('categories', 'habits', 'categories_user_order_idx', "
          "'habits_user_order_idx', 'habits_category_idx', "
          "'habit_options', 'habit_schedules', "
          "'habit_options_user_habit_order_idx', "
          "'habit_schedules_user_habit_idx', 'point_rules', "
          "'point_rules_user_habit_order_idx')",
        )
        .get();

    expect(entities.map((row) => row.read<String>('name')).toSet(), {
      'categories',
      'habits',
      'categories_user_order_idx',
      'habits_user_order_idx',
      'habits_category_idx',
      'habit_options',
      'habit_schedules',
      'habit_options_user_habit_order_idx',
      'habit_schedules_user_habit_idx',
      'point_rules',
      'point_rules_user_habit_order_idx',
    });
  });
}
