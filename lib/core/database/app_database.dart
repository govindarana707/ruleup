import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:ruleup/core/database/database_uuid.dart';
import 'package:ruleup/core/database/habit_date_converter.dart';
import 'package:ruleup/core/database/tables/categories.dart';
import 'package:ruleup/core/database/tables/check_ins.dart';
import 'package:ruleup/core/database/tables/habits.dart';
import 'package:ruleup/core/database/tables/habit_options.dart';
import 'package:ruleup/core/database/tables/habit_pauses.dart';
import 'package:ruleup/core/database/tables/habit_reminders.dart';
import 'package:ruleup/core/database/tables/habit_schedules.dart';
import 'package:ruleup/core/database/tables/local_users.dart';
import 'package:ruleup/core/database/tables/point_rules.dart';
import 'package:ruleup/core/database/tables/point_ledger.dart';
import 'package:ruleup/core/database/tables/rewards.dart';
import 'package:ruleup/core/database/tables/reward_image_operations.dart';
import 'package:ruleup/core/database/tables/reward_redemption_requests.dart';
import 'package:ruleup/core/database/tables/sync_metadata.dart';
import 'package:ruleup/core/database/tables/sync_queue.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    LocalUsers,
    SyncQueue,
    SyncMetadata,
    Categories,
    Habits,
    HabitOptions,
    HabitSchedules,
    PointRules,
    CheckIns,
    PointLedger,
    HabitPauses,
    Rewards,
    RewardImageOperations,
    RewardRedemptionRequests,
    HabitReminders,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.defaults() : super(driftDatabase(name: 'ruleup'));

  @override
  int get schemaVersion => 12;

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
        case 3:
          await migrator.createTable(habitOptions);
          await migrator.createTable(habitSchedules);
          await customStatement(
            'CREATE INDEX habit_options_user_habit_order_idx '
            'ON habit_options '
            '(user_id, habit_id, archived_at, sort_order)',
          );
          await customStatement(
            'CREATE INDEX habit_schedules_user_habit_idx '
            'ON habit_schedules (user_id, habit_id)',
          );
        case 4:
          await migrator.createTable(pointRules);
          await customStatement(
            'CREATE INDEX point_rules_user_habit_order_idx '
            'ON point_rules '
            '(user_id, habit_id, archived_at, sort_order)',
          );
        case 5:
          await migrator.createTable(checkIns);
          await customStatement(
            'CREATE INDEX check_ins_user_date_idx '
            'ON check_ins (user_id, habit_date)',
          );
        case 6:
          await migrator.createTable(pointLedger);
          await customStatement(
            'CREATE INDEX point_ledger_user_created_idx '
            'ON point_ledger (user_id, created_at)',
          );
        case 7:
          await migrator.createTable(habitPauses);
          await customStatement(
            'CREATE INDEX habit_pauses_user_habit_dates_idx '
            'ON habit_pauses (user_id, habit_id, start_date, end_date)',
          );
        case 8:
          // A v1 upgrade creates the current habits table in migration 2, so
          // the new columns already exist on that upgrade path.
          if (from > 1) {
            await migrator.addColumn(habits, habits.missedPenaltyEnabled);
            await migrator.addColumn(habits, habits.missedPenaltyPoints);
          }
        case 9:
          await migrator.createTable(rewards);
          await customStatement(
            'CREATE INDEX rewards_user_order_idx '
            'ON rewards (user_id, archived_at, sort_order)',
          );
        case 10:
          await migrator.createTable(habitReminders);
          await customStatement(
            'CREATE UNIQUE INDEX habit_reminders_user_habit_idx '
            'ON habit_reminders (user_id, habit_id)',
          );
        case 11:
          // Earlier upgrade paths create the current rewards table in v9.
          if (from >= 10) {
            await migrator.addColumn(rewards, rewards.imageKey);
          }
        case 12:
          // Earlier upgrade paths create the current ledger table in v6.
          if (from >= 6) {
            await migrator.addColumn(pointLedger, pointLedger.rewardId);
          }
          await migrator.createTable(rewardImageOperations);
          await migrator.createTable(rewardRedemptionRequests);
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
