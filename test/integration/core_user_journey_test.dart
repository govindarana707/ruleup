import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/sync/sync_service.dart';
import 'package:ruleup/core/sync/sync_transport.dart';
import 'package:ruleup/features/categories/data/category_repository.dart';
import 'package:ruleup/features/check_ins/data/check_in_repository.dart';
import 'package:ruleup/features/habits/data/habit_repository.dart';
import 'package:ruleup/features/habits/data/habit_schedule_repository.dart';
import 'package:ruleup/features/habits/domain/measurement_type.dart';
import 'package:ruleup/features/habits/domain/schedule_applicability.dart';
import 'package:ruleup/features/habits/domain/schedule_type.dart';
import 'package:ruleup/features/habits/domain/streak_calculator.dart';
import 'package:ruleup/features/points/data/point_ledger_repository.dart';
import 'package:ruleup/features/points/data/point_rule_repository.dart';
import 'package:ruleup/features/points/domain/point_rule_operator.dart';
import 'package:ruleup/features/reminders/data/habit_reminder_repository.dart';
import 'package:ruleup/features/rewards/data/reward_repository.dart';

void main() {
  test(
    'configured habit journey updates history, streak, wallet, and sync',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final transport = _JourneyTransport();
      final sync = SyncService(database, transport);
      final categories = CategoryRepository(database, sync);
      final habits = HabitRepository(database, sync);
      final schedules = HabitScheduleRepository(database, sync);
      final rules = PointRuleRepository(database, sync);
      final reminders = HabitReminderRepository(database, sync);
      final checkIns = CheckInRepository(
        database,
        sync,
        now: () => DateTime.utc(2026, 9, 7, 10),
      );
      final ledger = PointLedgerRepository(database, sync);
      final rewards = RewardRepository(database, sync);
      final user = await database
          .into(database.localUsers)
          .insertReturning(LocalUsersCompanion.insert());

      final category = await categories.create(
        userId: user.id,
        name: 'Learning',
      );
      final habit = await habits.create(
        userId: user.id,
        categoryId: category.id,
        name: 'Study',
        measurementType: MeasurementType.duration,
      );
      await schedules.create(
        userId: user.id,
        habitId: habit.id,
        scheduleType: ScheduleType.daily,
        scheduleConfig: '{}',
      );
      await rules.create(
        userId: user.id,
        habitId: habit.id,
        operator: PointRuleOperator.gte,
        valueMin: 30,
        points: 20,
      );
      await reminders.create(
        userId: user.id,
        habitId: habit.id,
        enabled: true,
        timeOfDay: '18:30',
      );

      final date = DateTime.utc(2026, 9, 7);
      final checkIn = await checkIns.create(
        userId: user.id,
        habitId: habit.id,
        habitDate: date,
        measuredValue: 40,
        note: 'Focused session',
      );
      expect(checkIn.awardedPoints, 20);
      expect(await checkIns.listForDate(user.id, date), [checkIn]);

      final streak = const StreakCalculator().calculate(
        startDate: date,
        throughDate: date,
        schedules: [
          HabitScheduleDefinition.fromConfig(
            type: ScheduleType.daily,
            scheduleConfig: '{}',
          ),
        ],
        checkInDates: [checkIn.habitDate],
        pauses: const [],
      );
      expect(streak.current, 1);
      expect(streak.longest, 1);

      final reward = await rewards.create(
        userId: user.id,
        name: 'Coffee break',
        pointsCost: 15,
      );
      await rewards.redeem(userId: user.id, rewardId: reward.id);
      final wallet = await ledger.getWallet(user.id);
      expect(wallet.availablePoints, 5);
      expect(wallet.lifetimeEarned, 20);
      expect(wallet.spentPoints, 15);

      final entityTypes = (await database.select(database.syncQueue).get())
          .map((item) => item.entityType)
          .toSet();
      expect(
        entityTypes,
        containsAll(<String>{
          'category',
          'habit',
          'habit_schedule',
          'point_rule',
          'habit_reminder',
          'check_in',
          'point_ledger',
          'reward',
        }),
      );

      final result = await sync.syncPending(user.id);
      expect(result.failed, 0);
      expect(await database.select(database.syncQueue).get(), isEmpty);
      expect(transport.sent, isNotEmpty);
    },
  );
}

class _JourneyTransport implements SyncTransport {
  final List<String> sent = [];

  @override
  Future<void> send(SyncQueueData item) async => sent.add(item.id);
}
