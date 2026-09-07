import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/core/utils/habit_date.dart';
import 'package:ruleup/features/categories/data/category_repository.dart';
import 'package:ruleup/features/categories/data/category_repository_provider.dart';
import 'package:ruleup/features/check_ins/data/check_in_repository.dart';
import 'package:ruleup/features/check_ins/data/check_in_repository_provider.dart';
import 'package:ruleup/features/habits/data/habit_option_repository.dart';
import 'package:ruleup/features/habits/data/habit_option_repository_provider.dart';
import 'package:ruleup/features/habits/data/habit_pause_repository.dart';
import 'package:ruleup/features/habits/data/habit_pause_repository_provider.dart';
import 'package:ruleup/features/habits/data/habit_repository.dart';
import 'package:ruleup/features/habits/data/habit_repository_provider.dart';
import 'package:ruleup/features/habits/data/habit_schedule_repository.dart';
import 'package:ruleup/features/habits/data/habit_schedule_repository_provider.dart';
import 'package:ruleup/features/habits/domain/schedule_applicability.dart';
import 'package:ruleup/features/habits/domain/schedule_type.dart';
import 'package:ruleup/features/habits/domain/streak_calculator.dart';
import 'package:ruleup/features/points/data/point_ledger_repository.dart';
import 'package:ruleup/features/points/data/point_ledger_repository_provider.dart';

final historyNowProvider = Provider<DateTime>((ref) => DateTime.now());

typedef HistoryQuery = ({String userId, DateTime date});

final historyCoordinatorProvider = Provider<HistoryCoordinator>(
  (ref) => HistoryCoordinator(
    categories: ref.watch(categoryRepositoryProvider),
    habits: ref.watch(habitRepositoryProvider),
    options: ref.watch(habitOptionRepositoryProvider),
    schedules: ref.watch(habitScheduleRepositoryProvider),
    pauses: ref.watch(habitPauseRepositoryProvider),
    checkIns: ref.watch(checkInRepositoryProvider),
    ledger: ref.watch(pointLedgerRepositoryProvider),
  ),
);

final historyDayProvider = FutureProvider.family<HistoryDayData, HistoryQuery>((
  ref,
  query,
) async {
  ref.watch(syncControllerProvider.select((state) => state.status));
  final now = ref.watch(historyNowProvider);
  return ref
      .watch(historyCoordinatorProvider)
      .load(userId: query.userId, selectedDate: query.date, now: now);
});

class HistoryCoordinator {
  const HistoryCoordinator({
    required this.categories,
    required this.habits,
    required this.options,
    required this.schedules,
    required this.pauses,
    required this.checkIns,
    required this.ledger,
  });

  final CategoryRepository categories;
  final HabitRepository habits;
  final HabitOptionRepository options;
  final HabitScheduleRepository schedules;
  final HabitPauseRepository pauses;
  final CheckInRepository checkIns;
  final PointLedgerRepository ledger;

  Future<HistoryDayData> load({
    required String userId,
    required DateTime selectedDate,
    required DateTime now,
  }) async {
    final date = normalizeHabitDate(selectedDate);
    final today = normalizeHabitDate(now);
    final categoryRows = await categories.list(userId, includeArchived: true);
    final categoryNames = {
      for (final category in categoryRows) category.id: category.name,
    };
    final habitRows = await habits.list(userId, includeArchived: true);
    final selectedCheckIns = await checkIns.listForDate(userId, date);
    final checkInByHabit = {
      for (final checkIn in selectedCheckIns) checkIn.habitId: checkIn,
    };
    final entries = <HistoryEntry>[];
    final habitFilters = <HistoryHabitFilter>[];
    var bestCurrent = 0;
    var bestLongest = 0;

    for (final habit in habitRows) {
      final createdDate = normalizeHabitDate(habit.createdAt);
      final archivedDate = habit.archivedAt == null
          ? null
          : normalizeHabitDate(habit.archivedAt!);
      final existedOnDate =
          !date.isBefore(createdDate) &&
          (archivedDate == null || !date.isAfter(archivedDate));
      final existedByToday = !today.isBefore(createdDate);
      if (!existedOnDate && !existedByToday) continue;

      final scheduleRows = await schedules.listForHabit(userId, habit.id);
      final definitions = scheduleRows
          .map(
            (row) => HabitScheduleDefinition.fromConfig(
              type: row.scheduleType,
              scheduleConfig: row.scheduleConfig,
            ),
          )
          .toList(growable: false);
      final pauseRows = await pauses.listForHabit(userId, habit.id);
      final pausePeriods = pauseRows
          .map(
            (row) => HabitPausePeriod(
              startDate: row.startDate,
              endDate: row.endDate,
            ),
          )
          .toList(growable: false);
      final history = await checkIns.listForHabit(userId, habit.id);
      final checkedToday = history.any(
        (checkIn) => habitDateKey(checkIn.habitDate) == habitDateKey(today),
      );
      final throughDate = checkedToday
          ? today
          : today.subtract(const Duration(days: 1));
      final streakThroughDate =
          archivedDate != null && archivedDate.isBefore(throughDate)
          ? archivedDate.subtract(const Duration(days: 1))
          : throughDate;
      if (!streakThroughDate.isBefore(createdDate)) {
        final streak = const StreakCalculator().calculate(
          startDate: createdDate,
          throughDate: streakThroughDate,
          schedules: definitions,
          checkInDates: history.map((checkIn) => checkIn.habitDate),
          pauses: pausePeriods,
        );
        if (habit.archivedAt == null && streak.current > bestCurrent) {
          bestCurrent = streak.current;
        }
        if (streak.longest > bestLongest) bestLongest = streak.longest;
      }

      habitFilters.add(HistoryHabitFilter(id: habit.id, name: habit.name));
      if (!existedOnDate) continue;

      final checkIn = checkInByHabit[habit.id];
      final paused = pausePeriods.any((pause) => pause.contains(date));
      final applicable = const ScheduleApplicability().isApplicable(
        habitDate: date,
        schedules: definitions,
      );
      final status = checkIn != null
          ? HistoryEntryStatus.completed
          : paused
          ? HistoryEntryStatus.paused
          : !applicable
          ? HistoryEntryStatus.nonScheduled
          : date.isBefore(today)
          ? HistoryEntryStatus.missed
          : HistoryEntryStatus.pending;
      final penalty = status == HistoryEntryStatus.missed
          ? await ledger.getForMissedCheckIn(userId, habit.id, date)
          : null;
      String? optionLabel;
      if (checkIn?.optionId != null) {
        optionLabel = (await options.getById(
          userId,
          checkIn!.optionId!,
        ))?.label;
      }
      entries.add(
        HistoryEntry(
          habitId: habit.id,
          habitName: habit.name,
          categoryName: habit.categoryId == null
              ? null
              : categoryNames[habit.categoryId],
          scheduleSummary: scheduleRows.isEmpty
              ? 'Daily'
              : _scheduleSummary(scheduleRows.first),
          status: status,
          selectedOption: optionLabel,
          measuredValue: checkIn?.measuredValue,
          points: checkIn?.awardedPoints ?? penalty?.points ?? 0,
          note: checkIn?.note,
          checkedInAt: checkIn?.checkedInAt,
        ),
      );
    }

    habitFilters.sort((left, right) => left.name.compareTo(right.name));
    return HistoryDayData(
      date: date,
      currentStreak: bestCurrent,
      longestStreak: bestLongest,
      habits: habitFilters,
      entries: entries,
    );
  }
}

enum HistoryEntryStatus { completed, missed, paused, nonScheduled, pending }

enum HistoryCompletionFilter { all, completed, missed }

class HistoryDayData {
  const HistoryDayData({
    required this.date,
    required this.currentStreak,
    required this.longestStreak,
    required this.habits,
    required this.entries,
  });

  final DateTime date;
  final int currentStreak;
  final int longestStreak;
  final List<HistoryHabitFilter> habits;
  final List<HistoryEntry> entries;
}

class HistoryHabitFilter {
  const HistoryHabitFilter({required this.id, required this.name});

  final String id;
  final String name;
}

class HistoryEntry {
  const HistoryEntry({
    required this.habitId,
    required this.habitName,
    required this.scheduleSummary,
    required this.status,
    required this.points,
    this.categoryName,
    this.selectedOption,
    this.measuredValue,
    this.note,
    this.checkedInAt,
  });

  final String habitId;
  final String habitName;
  final String? categoryName;
  final String scheduleSummary;
  final HistoryEntryStatus status;
  final String? selectedOption;
  final double? measuredValue;
  final int points;
  final String? note;
  final DateTime? checkedInAt;
}

String _scheduleSummary(HabitSchedule schedule) {
  final config = jsonDecode(schedule.scheduleConfig);
  final map = config is Map<String, dynamic> ? config : <String, dynamic>{};
  return switch (schedule.scheduleType) {
    ScheduleType.daily => 'Daily',
    ScheduleType.specificDays => _weekdaySummary(
      ((map['days'] as List?) ?? const []).whereType<int>(),
    ),
    ScheduleType.timesPerWeek => '${map['times'] ?? '?'}× weekly',
    ScheduleType.custom => 'Custom schedule',
  };
}

String _weekdaySummary(Iterable<int> weekdays) {
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final selected = weekdays
      .where((day) => day >= 1 && day <= 7)
      .map((day) => names[day - 1])
      .join(', ');
  return selected.isEmpty ? 'Specific days' : selected;
}
