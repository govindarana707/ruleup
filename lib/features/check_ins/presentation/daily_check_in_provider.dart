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
import 'package:ruleup/features/habits/domain/measurement_type.dart';
import 'package:ruleup/features/habits/domain/schedule_applicability.dart';
import 'package:ruleup/features/habits/domain/schedule_type.dart';
import 'package:ruleup/features/habits/domain/streak_calculator.dart';
import 'package:ruleup/features/reminders/data/habit_reminder_repository.dart';
import 'package:ruleup/features/reminders/data/habit_reminder_repository_provider.dart';

final checkInNowProvider = Provider<DateTime>((ref) => DateTime.now());

final dailyCheckInCoordinatorProvider = Provider<DailyCheckInCoordinator>(
  (ref) => DailyCheckInCoordinator(
    categories: ref.watch(categoryRepositoryProvider),
    habits: ref.watch(habitRepositoryProvider),
    options: ref.watch(habitOptionRepositoryProvider),
    schedules: ref.watch(habitScheduleRepositoryProvider),
    pauses: ref.watch(habitPauseRepositoryProvider),
    reminders: ref.watch(habitReminderRepositoryProvider),
    checkIns: ref.watch(checkInRepositoryProvider),
  ),
);

final dailyCheckInProvider = FutureProvider.family<DailyCheckInData, String>((
  ref,
  userId,
) async {
  ref.watch(syncControllerProvider.select((state) => state.status));
  final now = ref.watch(checkInNowProvider);
  return ref
      .watch(dailyCheckInCoordinatorProvider)
      .load(userId: userId, now: now);
});

typedef CheckInSubmitAction = Future<CheckInSubmitResult> Function(
  String userId,
  CheckInSubmission submission,
);

final checkInSubmitActionProvider = Provider<CheckInSubmitAction>(
  (ref) => ref.watch(dailyCheckInCoordinatorProvider).submit,
);

class DailyCheckInCoordinator {
  const DailyCheckInCoordinator({
    required this.categories,
    required this.habits,
    required this.options,
    required this.schedules,
    required this.pauses,
    required this.reminders,
    required this.checkIns,
  });

  final CategoryRepository categories;
  final HabitRepository habits;
  final HabitOptionRepository options;
  final HabitScheduleRepository schedules;
  final HabitPauseRepository pauses;
  final HabitReminderRepository reminders;
  final CheckInRepository checkIns;

  Future<DailyCheckInData> load({
    required String userId,
    required DateTime now,
  }) async {
    final today = normalizeHabitDate(now);
    final categoryRows = await categories.list(userId, includeArchived: true);
    final categoryNames = {
      for (final category in categoryRows) category.id: category.name,
    };
    final habitRows = await habits.list(userId);
    final todayRows = await checkIns.listForDate(userId, today);
    final checkInByHabit = {
      for (final checkIn in todayRows) checkIn.habitId: checkIn,
    };
    final entries = <DailyHabitEntry>[];

    for (final habit in habitRows) {
      final scheduleRows = await schedules.listForHabit(userId, habit.id);
      final definitions = scheduleRows
          .map(
            (row) => HabitScheduleDefinition.fromConfig(
              type: row.scheduleType,
              scheduleConfig: row.scheduleConfig,
            ),
          )
          .toList(growable: false);
      if (!const ScheduleApplicability().isApplicable(
        habitDate: today,
        schedules: definitions,
      )) {
        continue;
      }
      final pauseRows = await pauses.listForHabit(userId, habit.id);
      final pausePeriods = pauseRows
          .map(
            (row) => HabitPausePeriod(
              startDate: row.startDate,
              endDate: row.endDate,
            ),
          )
          .toList(growable: false);
      if (pausePeriods.any((pause) => pause.contains(today))) continue;

      final checkIn = checkInByHabit[habit.id];
      final history = await checkIns.listForHabit(userId, habit.id);
      final completedCheckIn =
          checkIn != null &&
          (habit.measurementType != MeasurementType.yesNo ||
              checkIn.measuredValue != 0);
      final completedHistory = habit.measurementType == MeasurementType.yesNo
          ? history.where((row) => row.measuredValue != 0)
          : history;
      final throughDate = !completedCheckIn
          ? today.subtract(const Duration(days: 1))
          : today;
      var streak = 0;
      final startDate = normalizeHabitDate(habit.createdAt);
      if (!throughDate.isBefore(startDate)) {
        streak = const StreakCalculator()
            .calculate(
              startDate: startDate,
              throughDate: throughDate,
              schedules: definitions,
              checkInDates: completedHistory.map((row) => row.habitDate),
              pauses: pausePeriods,
            )
            .current;
      }
      final optionRows = await options.listForHabit(userId, habit.id);
      final reminder = await reminders.getForHabit(userId, habit.id);
      entries.add(
        DailyHabitEntry(
          id: habit.id,
          name: habit.name,
          categoryName: habit.categoryId == null
              ? null
              : categoryNames[habit.categoryId],
          measurementType: habit.measurementType,
          scheduleSummary: scheduleRows.isEmpty
              ? 'Daily'
              : _scheduleSummary(scheduleRows.first),
          reminderTime: reminder?.enabled == true ? reminder!.timeOfDay : null,
          currentStreak: streak,
          options: optionRows
              .map(
                (option) => CheckInOption(
                  id: option.id,
                  label: option.label,
                  numericValue: option.numericValue,
                ),
              )
              .toList(growable: false),
          checkIn: checkIn == null
              ? null
              : ExistingCheckIn(
                  id: checkIn.id,
                  optionId: checkIn.optionId,
                  measuredValue: checkIn.measuredValue,
                  note: checkIn.note,
                  awardedPoints: checkIn.awardedPoints,
                  editableUntil: checkIn.editableUntil,
                  locked: now.toUtc().isAfter(checkIn.editableUntil),
                  completed:
                      habit.measurementType != MeasurementType.yesNo ||
                      checkIn.measuredValue != 0,
                ),
        ),
      );
    }
    return DailyCheckInData(date: today, habits: entries);
  }

  Future<CheckInSubmitResult> submit(
    String userId,
    CheckInSubmission submission,
  ) async {
    final CheckIn checkIn;
    if (submission.checkInId == null) {
      checkIn = await checkIns.create(
        userId: userId,
        habitId: submission.habitId,
        habitDate: submission.habitDate,
        optionId: submission.optionId,
        measuredValue: submission.measuredValue,
        note: submission.note,
        completed: submission.completed,
      );
    } else {
      checkIn =
          await checkIns.update(
            userId: userId,
            id: submission.checkInId!,
            optionId: submission.optionId,
            measuredValue: submission.measuredValue,
            note: submission.note,
            completed: submission.completed,
          ) ??
          (throw StateError('Check-in not found'));
    }
    return CheckInSubmitResult(
      points: checkIn.awardedPoints,
      updated: submission.checkInId != null,
    );
  }
}

class DailyCheckInData {
  const DailyCheckInData({required this.date, required this.habits});

  final DateTime date;
  final List<DailyHabitEntry> habits;

  int get completedCount => habits.where((habit) => habit.isCompleted).length;
}

class DailyHabitEntry {
  const DailyHabitEntry({
    required this.id,
    required this.name,
    required this.measurementType,
    required this.scheduleSummary,
    required this.currentStreak,
    this.categoryName,
    this.reminderTime,
    this.options = const [],
    this.checkIn,
  });

  final String id;
  final String name;
  final String? categoryName;
  final MeasurementType measurementType;
  final String scheduleSummary;
  final String? reminderTime;
  final int currentStreak;
  final List<CheckInOption> options;
  final ExistingCheckIn? checkIn;

  bool get isCompleted => checkIn?.completed == true;
}

class CheckInOption {
  const CheckInOption({
    required this.id,
    required this.label,
    this.numericValue,
  });

  final String id;
  final String label;
  final double? numericValue;
}

class ExistingCheckIn {
  const ExistingCheckIn({
    required this.id,
    required this.awardedPoints,
    required this.editableUntil,
    required this.locked,
    this.completed = true,
    this.optionId,
    this.measuredValue,
    this.note,
  });

  final String id;
  final String? optionId;
  final double? measuredValue;
  final String? note;
  final int awardedPoints;
  final DateTime editableUntil;
  final bool locked;
  final bool completed;
}

class CheckInSubmission {
  const CheckInSubmission({
    required this.habitId,
    required this.habitDate,
    this.checkInId,
    this.optionId,
    this.measuredValue,
    this.note,
    this.completed = true,
  });

  final String habitId;
  final DateTime habitDate;
  final String? checkInId;
  final String? optionId;
  final double? measuredValue;
  final String? note;
  final bool completed;
}

class CheckInSubmitResult {
  const CheckInSubmitResult({required this.points, required this.updated});

  final int points;
  final bool updated;
}

String _scheduleSummary(HabitSchedule schedule) {
  final config = jsonDecode(schedule.scheduleConfig);
  final map = config is Map<String, dynamic> ? config : <String, dynamic>{};
  return switch (schedule.scheduleType) {
    ScheduleType.daily => 'Daily',
    ScheduleType.specificDays => _weekdaySummary(
      ((map['days'] as List?) ?? const []).whereType<int>(),
    ),
    ScheduleType.timesPerWeek => '${map['times'] ?? '?'}× this week',
    ScheduleType.custom => 'Scheduled today',
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
