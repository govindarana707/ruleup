import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/features/habits/domain/schedule_applicability.dart';
import 'package:ruleup/features/habits/domain/schedule_type.dart';
import 'package:ruleup/features/habits/domain/streak_calculator.dart';

void main() {
  const applicability = ScheduleApplicability();
  const streaks = StreakCalculator();

  test('daily schedule applies every day', () {
    final schedule = HabitScheduleDefinition.fromConfig(
      type: ScheduleType.daily,
      scheduleConfig: '{}',
    );

    expect(
      applicability.isApplicable(
        habitDate: DateTime(2026, 1, 6),
        schedules: [schedule],
      ),
      isTrue,
    );
  });

  test('specific-days schedule applies only to configured weekdays', () {
    final schedule = HabitScheduleDefinition.fromConfig(
      type: ScheduleType.specificDays,
      scheduleConfig: '{"days":[1,3,5]}',
    );

    expect(
      applicability.isApplicable(
        habitDate: DateTime.utc(2026, 1, 5),
        schedules: [schedule],
      ),
      isTrue,
    );
    expect(
      applicability.isApplicable(
        habitDate: DateTime.utc(2026, 1, 6),
        schedules: [schedule],
      ),
      isFalse,
    );
  });

  test(
    'times-per-week schedule uses deterministic spread or explicit days',
    () {
      final spread = HabitScheduleDefinition.fromConfig(
        type: ScheduleType.timesPerWeek,
        scheduleConfig: '{"times":3}',
      );
      final explicit = HabitScheduleDefinition.fromConfig(
        type: ScheduleType.timesPerWeek,
        scheduleConfig: '{"times":2,"days":[2,6]}',
      );

      expect(spread.weekdays, {
        DateTime.monday,
        DateTime.thursday,
        DateTime.sunday,
      });
      expect(explicit.weekdays, {DateTime.tuesday, DateTime.saturday});
    },
  );

  test('custom schedule applies only to explicit habit dates', () {
    final schedule = HabitScheduleDefinition.fromConfig(
      type: ScheduleType.custom,
      scheduleConfig: '{"dates":["2026-02-01","2026-02-10"]}',
    );

    expect(
      applicability.isApplicable(
        habitDate: DateTime(2026, 2, 10, 23),
        schedules: [schedule],
      ),
      isTrue,
    );
    expect(
      applicability.isApplicable(
        habitDate: DateTime(2026, 2, 9),
        schedules: [schedule],
      ),
      isFalse,
    );
  });

  test('non-scheduled days do not break or increment a streak', () {
    final schedule = HabitScheduleDefinition.fromConfig(
      type: ScheduleType.specificDays,
      scheduleConfig: '{"days":[1,3,5]}',
    );
    final result = streaks.calculate(
      startDate: DateTime(2026, 1, 5),
      throughDate: DateTime(2026, 1, 9),
      schedules: [schedule],
      checkInDates: [
        DateTime(2026, 1, 5),
        DateTime(2026, 1, 7),
        DateTime(2026, 1, 9),
      ],
      pauses: const [],
    );

    expect(result.current, 3);
    expect(result.longest, 3);
  });

  test('paused applicable days freeze the streak', () {
    final daily = HabitScheduleDefinition.fromConfig(
      type: ScheduleType.daily,
      scheduleConfig: '{}',
    );
    final result = streaks.calculate(
      startDate: DateTime(2026, 1, 1),
      throughDate: DateTime(2026, 1, 5),
      schedules: [daily],
      checkInDates: [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 2),
        DateTime(2026, 1, 4),
        DateTime(2026, 1, 5),
      ],
      pauses: [
        HabitPausePeriod(
          startDate: DateTime(2026, 1, 3),
          endDate: DateTime(2026, 1, 3),
        ),
      ],
    );

    expect(result.current, 4);
    expect(result.longest, 4);
  });

  test('missed applicable days break current but preserve longest streak', () {
    final daily = HabitScheduleDefinition.fromConfig(
      type: ScheduleType.daily,
      scheduleConfig: '{}',
    );
    final result = streaks.calculate(
      startDate: DateTime(2026, 1, 1),
      throughDate: DateTime(2026, 1, 8),
      schedules: [daily],
      checkInDates: [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 2),
        DateTime(2026, 1, 4),
        DateTime(2026, 1, 5),
        DateTime(2026, 1, 6),
        DateTime(2026, 1, 8),
      ],
      pauses: const [],
    );

    expect(result.current, 1);
    expect(result.longest, 3);
  });
}
