import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/core/utils/habit_date.dart';
import 'package:ruleup/features/check_ins/data/check_in_repository_provider.dart';
import 'package:ruleup/features/habits/data/habit_pause_repository_provider.dart';
import 'package:ruleup/features/habits/data/habit_repository_provider.dart';
import 'package:ruleup/features/habits/data/habit_schedule_repository_provider.dart';
import 'package:ruleup/features/habits/domain/schedule_applicability.dart';
import 'package:ruleup/features/habits/domain/streak_calculator.dart';
import 'package:ruleup/features/points/data/point_ledger_repository_provider.dart';
import 'package:ruleup/features/reminders/data/habit_reminder_repository_provider.dart';
import 'package:ruleup/features/reminders/domain/reminder_time.dart';

final homeNowProvider = Provider<DateTime>((ref) => DateTime.now());

final homeDashboardProvider = FutureProvider.family<HomeDashboardData, String>((
  ref,
  userId,
) async {
  ref.watch(syncControllerProvider.select((state) => state.status));
  final now = ref.watch(homeNowProvider);
  final today = normalizeHabitDate(now);
  final habitRepository = ref.watch(habitRepositoryProvider);
  final checkIns = ref.watch(checkInRepositoryProvider);
  final schedules = ref.watch(habitScheduleRepositoryProvider);
  final pauses = ref.watch(habitPauseRepositoryProvider);

  final habits = await habitRepository.list(userId);
  final wallet = await ref
      .watch(pointLedgerRepositoryProvider)
      .getWallet(userId);
  final todayCheckIns = await checkIns.listForDate(userId, today);
  final reminders = await ref
      .watch(habitReminderRepositoryProvider)
      .list(userId);
  final completedHabitIds = todayCheckIns
      .map((checkIn) => checkIn.habitId)
      .toSet();
  final checkInByHabitId = {
    for (final checkIn in todayCheckIns) checkIn.habitId: checkIn,
  };

  final contexts = <String, _HabitContext>{};
  final todayHabits = <TodayHabitSummary>[];
  var applicableToday = 0;
  var completedToday = 0;
  var bestStreak = 0;
  String? bestStreakHabit;

  for (final habit in habits) {
    final habitSchedules = await schedules.listForHabit(userId, habit.id);
    final definitions = habitSchedules
        .map(
          (schedule) => HabitScheduleDefinition.fromConfig(
            type: schedule.scheduleType,
            scheduleConfig: schedule.scheduleConfig,
          ),
        )
        .toList(growable: false);
    final habitPauses = (await pauses.listForHabit(userId, habit.id))
        .map(
          (pause) => HabitPausePeriod(
            startDate: pause.startDate,
            endDate: pause.endDate,
          ),
        )
        .toList(growable: false);
    final pausedToday = habitPauses.any((pause) => pause.contains(today));
    final appliesToday =
        !pausedToday &&
        const ScheduleApplicability().isApplicable(
          habitDate: today,
          schedules: definitions,
        );
    if (appliesToday) {
      applicableToday++;
      final checkIn = checkInByHabitId[habit.id];
      if (checkIn != null) completedToday++;
      todayHabits.add(
        TodayHabitSummary(
          habitId: habit.id,
          habitName: habit.name,
          isCompleted: checkIn != null,
          awardedPoints: checkIn?.awardedPoints,
        ),
      );
    }

    final history = await checkIns.listForHabit(userId, habit.id);
    final checkedToday = completedHabitIds.contains(habit.id);
    final throughDate = checkedToday
        ? today
        : today.subtract(const Duration(days: 1));
    var currentStreak = 0;
    final startDate = normalizeHabitDate(habit.createdAt);
    if (!throughDate.isBefore(startDate)) {
      currentStreak = const StreakCalculator()
          .calculate(
            startDate: startDate,
            throughDate: throughDate,
            schedules: definitions,
            checkInDates: history.map((checkIn) => checkIn.habitDate),
            pauses: habitPauses,
          )
          .current;
    }
    if (currentStreak > bestStreak) {
      bestStreak = currentStreak;
      bestStreakHabit = habit.name;
    }
    contexts[habit.id] = _HabitContext(
      habit: habit,
      schedules: definitions,
      pauses: habitPauses,
    );
  }

  final upcoming = <UpcomingReminder>[];
  for (final reminder in reminders.where((item) => item.enabled)) {
    final context = contexts[reminder.habitId];
    if (context == null) continue;
    final next = _nextReminder(
      now: now,
      time: ReminderTime.parse(reminder.timeOfDay),
      schedules: context.schedules,
      pauses: context.pauses,
    );
    if (next != null) {
      upcoming.add(
        UpcomingReminder(
          habitId: context.habit.id,
          habitName: context.habit.name,
          scheduledAt: next,
        ),
      );
    }
  }
  upcoming.sort((left, right) => left.scheduledAt.compareTo(right.scheduledAt));

  return HomeDashboardData(
    availablePoints: wallet.availablePoints,
    currentStreak: bestStreak,
    streakHabitName: bestStreakHabit,
    completedToday: completedToday,
    applicableToday: applicableToday,
    activeHabitCount: habits.length,
    todayHabits: todayHabits,
    upcomingReminders: upcoming.take(3).toList(growable: false),
  );
});

DateTime? _nextReminder({
  required DateTime now,
  required ReminderTime time,
  required List<HabitScheduleDefinition> schedules,
  required List<HabitPausePeriod> pauses,
}) {
  final firstDate = normalizeHabitDate(now);
  for (var offset = 0; offset < 8; offset++) {
    final date = firstDate.add(Duration(days: offset));
    if (pauses.any((pause) => pause.contains(date))) continue;
    if (!const ScheduleApplicability().isApplicable(
      habitDate: date,
      schedules: schedules,
    )) {
      continue;
    }
    final scheduledAt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (scheduledAt.isAfter(now)) return scheduledAt;
  }
  return null;
}

class _HabitContext {
  const _HabitContext({
    required this.habit,
    required this.schedules,
    required this.pauses,
  });

  final Habit habit;
  final List<HabitScheduleDefinition> schedules;
  final List<HabitPausePeriod> pauses;
}

class HomeDashboardData {
  const HomeDashboardData({
    required this.availablePoints,
    required this.currentStreak,
    required this.completedToday,
    required this.applicableToday,
    required this.activeHabitCount,
    this.streakHabitName,
    this.todayHabits = const [],
    this.upcomingReminders = const [],
  });

  final int availablePoints;
  final int currentStreak;
  final String? streakHabitName;
  final int completedToday;
  final int applicableToday;
  final int activeHabitCount;
  final List<TodayHabitSummary> todayHabits;
  final List<UpcomingReminder> upcomingReminders;

  double get progress =>
      applicableToday == 0 ? 0 : (completedToday / applicableToday).clamp(0, 1);
}

class TodayHabitSummary {
  const TodayHabitSummary({
    required this.habitId,
    required this.habitName,
    required this.isCompleted,
    this.awardedPoints,
  });

  final String habitId;
  final String habitName;
  final bool isCompleted;
  final int? awardedPoints;
}

class UpcomingReminder {
  const UpcomingReminder({
    required this.habitId,
    required this.habitName,
    required this.scheduledAt,
  });

  final String habitId;
  final String habitName;
  final DateTime scheduledAt;
}
