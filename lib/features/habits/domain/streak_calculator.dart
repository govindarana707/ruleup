import 'package:ruleup/core/utils/habit_date.dart';
import 'package:ruleup/features/habits/domain/schedule_applicability.dart';

class HabitPausePeriod {
  HabitPausePeriod({required DateTime startDate, required DateTime endDate})
    : startDate = normalizeHabitDate(startDate),
      endDate = normalizeHabitDate(endDate) {
    if (this.endDate.isBefore(this.startDate)) {
      throw ArgumentError('endDate must not be before startDate');
    }
  }

  final DateTime startDate;
  final DateTime endDate;

  bool contains(DateTime date) {
    final normalized = normalizeHabitDate(date);
    return !normalized.isBefore(startDate) && !normalized.isAfter(endDate);
  }
}

class StreakResult {
  const StreakResult({required this.current, required this.longest});

  final int current;
  final int longest;
}

class StreakCalculator {
  const StreakCalculator({ScheduleApplicability? applicability})
    : _applicability = applicability ?? const ScheduleApplicability();

  final ScheduleApplicability _applicability;

  StreakResult calculate({
    required DateTime startDate,
    required DateTime throughDate,
    required Iterable<HabitScheduleDefinition> schedules,
    required Iterable<DateTime> checkInDates,
    required Iterable<HabitPausePeriod> pauses,
  }) {
    final firstDate = normalizeHabitDate(startDate);
    final lastDate = normalizeHabitDate(throughDate);
    if (lastDate.isBefore(firstDate)) {
      throw ArgumentError('throughDate must not be before startDate');
    }

    final completedDates = checkInDates.map(habitDateKey).toSet();
    final pausePeriods = pauses.toList();
    var current = 0;
    var longest = 0;

    for (
      var date = firstDate;
      !date.isAfter(lastDate);
      date = date.add(const Duration(days: 1))
    ) {
      if (pausePeriods.any((pause) => pause.contains(date))) continue;
      if (!_applicability.isApplicable(habitDate: date, schedules: schedules)) {
        continue;
      }
      if (completedDates.contains(habitDateKey(date))) {
        current++;
        if (current > longest) longest = current;
      } else {
        current = 0;
      }
    }
    return StreakResult(current: current, longest: longest);
  }
}
