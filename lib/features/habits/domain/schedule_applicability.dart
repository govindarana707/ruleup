import 'dart:convert';

import 'package:ruleup/core/utils/habit_date.dart';
import 'package:ruleup/features/habits/domain/schedule_type.dart';

class HabitScheduleDefinition {
  HabitScheduleDefinition._({
    required this.type,
    required this.weekdays,
    required this.customDates,
  });

  factory HabitScheduleDefinition.fromConfig({
    required ScheduleType type,
    required String scheduleConfig,
  }) {
    final decoded = jsonDecode(scheduleConfig);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Schedule config must be a JSON object');
    }

    return switch (type) {
      ScheduleType.daily => HabitScheduleDefinition._(
        type: type,
        weekdays: const {},
        customDates: const {},
      ),
      ScheduleType.specificDays => HabitScheduleDefinition._(
        type: type,
        weekdays: _readWeekdays(decoded['days']),
        customDates: const {},
      ),
      ScheduleType.timesPerWeek => _timesPerWeek(decoded),
      ScheduleType.custom => HabitScheduleDefinition._(
        type: type,
        weekdays: const {},
        customDates: _readDates(decoded['dates']),
      ),
    };
  }

  final ScheduleType type;
  final Set<int> weekdays;
  final Set<String> customDates;

  static HabitScheduleDefinition _timesPerWeek(Map<String, dynamic> config) {
    final times = config['times'];
    if (times is! int || times < 1 || times > DateTime.daysPerWeek) {
      throw const FormatException('times must be an integer from 1 to 7');
    }
    final configuredDays = config['days'];
    final weekdays = configuredDays == null
        ? _evenlySpacedWeekdays(times)
        : _readWeekdays(configuredDays);
    if (weekdays.length != times) {
      throw const FormatException('days must contain exactly times weekdays');
    }
    return HabitScheduleDefinition._(
      type: ScheduleType.timesPerWeek,
      weekdays: weekdays,
      customDates: const {},
    );
  }

  static Set<int> _readWeekdays(Object? value) {
    if (value is! List || value.isEmpty) {
      throw const FormatException('days must be a non-empty array');
    }
    final weekdays = <int>{};
    for (final day in value) {
      if (day is! int || day < DateTime.monday || day > DateTime.sunday) {
        throw const FormatException('weekdays must be integers from 1 to 7');
      }
      if (!weekdays.add(day)) {
        throw const FormatException('weekdays must not contain duplicates');
      }
    }
    return Set.unmodifiable(weekdays);
  }

  static Set<String> _readDates(Object? value) {
    if (value is! List || value.isEmpty) {
      throw const FormatException('dates must be a non-empty array');
    }
    final dates = <String>{};
    for (final date in value) {
      if (date is! String) {
        throw const FormatException('custom dates must be strings');
      }
      dates.add(habitDateKey(parseHabitDate(date)));
    }
    return Set.unmodifiable(dates);
  }

  static Set<int> _evenlySpacedWeekdays(int times) {
    if (times == 1) return const {DateTime.monday};
    final weekdays = <int>{};
    for (var index = 0; index < times; index++) {
      final offset = (index * 6 / (times - 1)).round();
      weekdays.add(DateTime.monday + offset);
    }
    return Set.unmodifiable(weekdays);
  }
}

class ScheduleApplicability {
  const ScheduleApplicability();

  bool isApplicable({
    required DateTime habitDate,
    required Iterable<HabitScheduleDefinition> schedules,
  }) {
    final definitions = schedules.toList();
    if (definitions.isEmpty) return true;
    final date = normalizeHabitDate(habitDate);
    return definitions.any((schedule) => _applies(schedule, date));
  }

  bool _applies(HabitScheduleDefinition schedule, DateTime date) {
    return switch (schedule.type) {
      ScheduleType.daily => true,
      ScheduleType.specificDays ||
      ScheduleType.timesPerWeek => schedule.weekdays.contains(date.weekday),
      ScheduleType.custom => schedule.customDates.contains(habitDateKey(date)),
    };
  }
}
