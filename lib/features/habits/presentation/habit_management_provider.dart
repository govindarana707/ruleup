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
import 'package:ruleup/features/points/data/point_rule_repository.dart';
import 'package:ruleup/features/points/data/point_rule_repository_provider.dart';
import 'package:ruleup/features/points/domain/point_rule_operator.dart';
import 'package:ruleup/features/reminders/data/habit_reminder_repository.dart';
import 'package:ruleup/features/reminders/data/habit_reminder_repository_provider.dart';

final habitManagementCoordinatorProvider = Provider<HabitManagementCoordinator>(
  (ref) => HabitManagementCoordinator(
    categories: ref.watch(categoryRepositoryProvider),
    habits: ref.watch(habitRepositoryProvider),
    options: ref.watch(habitOptionRepositoryProvider),
    schedules: ref.watch(habitScheduleRepositoryProvider),
    rules: ref.watch(pointRuleRepositoryProvider),
    pauses: ref.watch(habitPauseRepositoryProvider),
    reminders: ref.watch(habitReminderRepositoryProvider),
    checkIns: ref.watch(checkInRepositoryProvider),
  ),
);

final habitCatalogProvider = FutureProvider.family<HabitCatalog, String>((
  ref,
  userId,
) async {
  ref.watch(syncControllerProvider.select((state) => state.status));
  return ref.watch(habitManagementCoordinatorProvider).loadCatalog(userId);
});

typedef HabitDraftLoader = Future<HabitDraft> Function(
  String userId,
  String habitId,
);
typedef HabitSaveAction = Future<String> Function(
  String userId,
  HabitDraft draft,
);
typedef HabitMutationAction = Future<void> Function(
  String userId,
  String habitId,
);
typedef CategoryCreateAction = Future<CategoryChoice> Function(
  String userId,
  String name,
);

final habitDraftLoaderProvider = Provider<HabitDraftLoader>(
  (ref) => ref.watch(habitManagementCoordinatorProvider).loadDraft,
);
final habitSaveActionProvider = Provider<HabitSaveAction>(
  (ref) => ref.watch(habitManagementCoordinatorProvider).save,
);
final habitArchiveActionProvider = Provider<HabitMutationAction>(
  (ref) => ref.watch(habitManagementCoordinatorProvider).archive,
);
final habitRestoreActionProvider = Provider<HabitMutationAction>(
  (ref) => ref.watch(habitManagementCoordinatorProvider).restore,
);
final categoryCreateActionProvider = Provider<CategoryCreateAction>(
  (ref) => ref.watch(habitManagementCoordinatorProvider).createCategory,
);

class HabitManagementCoordinator {
  const HabitManagementCoordinator({
    required this.categories,
    required this.habits,
    required this.options,
    required this.schedules,
    required this.rules,
    required this.pauses,
    required this.reminders,
    required this.checkIns,
  });

  final CategoryRepository categories;
  final HabitRepository habits;
  final HabitOptionRepository options;
  final HabitScheduleRepository schedules;
  final PointRuleRepository rules;
  final HabitPauseRepository pauses;
  final HabitReminderRepository reminders;
  final CheckInRepository checkIns;

  Future<HabitCatalog> loadCatalog(String userId) async {
    final categoryRows = await categories.list(userId, includeArchived: true);
    final categoryNames = {
      for (final category in categoryRows) category.id: category.name,
    };
    final habitRows = await habits.list(userId, includeArchived: true);
    final entries = <HabitListEntry>[];
    final today = normalizeHabitDate(DateTime.now());

    for (final habit in habitRows) {
      final scheduleRows = await schedules.listForHabit(userId, habit.id);
      final pauseRows = await pauses.listForHabit(userId, habit.id);
      final reminder = await reminders.getForHabit(userId, habit.id);
      final history = await checkIns.listForHabit(userId, habit.id);
      final completedHistory = habit.measurementType == MeasurementType.yesNo
          ? history.where((row) => row.measuredValue != 0)
          : history;
      final definitions = scheduleRows
          .map(
            (row) => HabitScheduleDefinition.fromConfig(
              type: row.scheduleType,
              scheduleConfig: row.scheduleConfig,
            ),
          )
          .toList(growable: false);
      final pausePeriods = pauseRows
          .map(
            (row) => HabitPausePeriod(
              startDate: row.startDate,
              endDate: row.endDate,
            ),
          )
          .toList(growable: false);
      final checkedToday = history.any(
        (row) => habitDateKey(row.habitDate) == habitDateKey(today),
      );
      final throughDate = checkedToday
          ? today
          : today.subtract(const Duration(days: 1));
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
      entries.add(
        HabitListEntry(
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
          archived: habit.archivedAt != null,
        ),
      );
    }

    return HabitCatalog(
      habits: entries,
      categories: categoryRows
          .where((row) => row.archivedAt == null)
          .map((row) => CategoryChoice(id: row.id, name: row.name))
          .toList(growable: false),
    );
  }

  Future<HabitDraft> loadDraft(String userId, String habitId) async {
    final habit = await habits.getById(userId, habitId);
    if (habit == null) throw StateError('Habit not found');
    final optionRows = await options.listForHabit(userId, habitId);
    final scheduleRows = await schedules.listForHabit(userId, habitId);
    final ruleRows = await rules.listForHabit(userId, habitId);
    final pauseRows = await pauses.listForHabit(userId, habitId);
    final reminder = await reminders.getForHabit(userId, habitId);

    final draft = HabitDraft(
      id: habit.id,
      name: habit.name,
      categoryId: habit.categoryId,
      measurementType: habit.measurementType,
      missedPenaltyEnabled: habit.missedPenaltyEnabled,
      missedPenaltyPoints: habit.missedPenaltyPoints.toString(),
      reminderEnabled: reminder?.enabled ?? false,
      reminderTime: reminder?.timeOfDay ?? '08:00',
      reminderId: reminder?.id,
      options: optionRows
          .map(
            (row) => HabitOptionDraft(
              id: row.id,
              label: row.label,
              numericValue: row.numericValue?.toString() ?? '',
            ),
          )
          .toList(),
      rules: ruleRows
          .map(
            (row) => PointRuleDraft(
              id: row.id,
              operator: row.operator,
              valueMin: row.valueMin?.toString() ?? '',
              valueMax: row.valueMax?.toString() ?? '',
              points: row.points.toString(),
            ),
          )
          .toList(),
      pauses: pauseRows
          .map(
            (row) => HabitPauseDraft(
              id: row.id,
              startDate: row.startDate,
              endDate: row.endDate,
            ),
          )
          .toList(),
    );
    if (scheduleRows.isNotEmpty) {
      draft.scheduleId = scheduleRows.first.id;
      draft.scheduleType = scheduleRows.first.scheduleType;
      final config = jsonDecode(scheduleRows.first.scheduleConfig);
      if (config is Map<String, dynamic>) {
        draft.scheduleDays = ((config['days'] as List?) ?? const [])
            .whereType<int>()
            .toSet();
        draft.timesPerWeek = config['times'] is int
            ? config['times'] as int
            : 3;
        draft.customDates = ((config['dates'] as List?) ?? const [])
            .whereType<String>()
            .map(parseHabitDate)
            .toList();
      }
    }
    return draft;
  }

  Future<CategoryChoice> createCategory(String userId, String name) async {
    final existing = await categories.list(userId);
    final normalized = name.trim().toLowerCase();
    if (existing.any((item) => item.name.toLowerCase() == normalized)) {
      throw ArgumentError('A category with this name already exists.');
    }
    final row = await categories.create(
      userId: userId,
      name: name,
      sortOrder: existing.length,
    );
    return CategoryChoice(id: row.id, name: row.name);
  }

  Future<String> save(String userId, HabitDraft draft) async {
    final validation = draft.validate();
    if (validation != null) throw ArgumentError(validation);
    final penaltyPoints = draft.missedPenaltyEnabled
        ? int.parse(draft.missedPenaltyPoints.trim())
        : 0;
    final Habit habit;
    if (draft.id == null) {
      habit = await habits.create(
        userId: userId,
        name: draft.name,
        categoryId: draft.categoryId,
        measurementType: draft.measurementType,
        missedPenaltyEnabled: draft.missedPenaltyEnabled,
        missedPenaltyPoints: penaltyPoints,
      );
      draft.id = habit.id;
    } else {
      habit =
          await habits.update(
            userId: userId,
            id: draft.id!,
            name: draft.name,
            categoryId: draft.categoryId,
            measurementType: draft.measurementType,
            sortOrder: 0,
            missedPenaltyEnabled: draft.missedPenaltyEnabled,
            missedPenaltyPoints: penaltyPoints,
          ) ??
          (throw StateError('Habit not found'));
    }

    await _saveOptions(userId, habit.id, draft.options);
    await _saveSchedule(userId, habit.id, draft);
    await _saveRules(userId, habit.id, draft.rules);
    await _savePauses(userId, habit.id, draft.pauses);
    await _saveReminder(userId, habit.id, draft);
    return habit.id;
  }

  Future<void> archive(String userId, String habitId) async {
    if (!await habits.archive(userId, habitId)) {
      throw StateError('Habit not found');
    }
  }

  Future<void> restore(String userId, String habitId) async {
    if (!await habits.restore(userId, habitId)) {
      throw StateError('Habit not found');
    }
  }

  Future<void> _saveOptions(
    String userId,
    String habitId,
    List<HabitOptionDraft> drafts,
  ) async {
    final existing = await options.listForHabit(userId, habitId);
    final keptIds = drafts.map((item) => item.id).whereType<String>().toSet();
    for (final row in existing.where((item) => !keptIds.contains(item.id))) {
      await options.archive(userId, row.id);
    }
    for (var index = 0; index < drafts.length; index++) {
      final draft = drafts[index];
      final numeric = draft.numericValue.trim().isEmpty
          ? null
          : double.parse(draft.numericValue.trim());
      if (draft.id == null) {
        final created = await options.create(
          userId: userId,
          habitId: habitId,
          label: draft.label,
          numericValue: numeric,
          sortOrder: index,
        );
        draft.id = created.id;
      } else {
        await options.update(
          userId: userId,
          id: draft.id!,
          habitId: habitId,
          label: draft.label,
          numericValue: numeric,
          sortOrder: index,
        );
      }
    }
  }

  Future<void> _saveSchedule(
    String userId,
    String habitId,
    HabitDraft draft,
  ) async {
    final existing = await schedules.listForHabit(userId, habitId);
    final config = draft.scheduleConfig;
    if (draft.scheduleId == null) {
      final created = await schedules.create(
        userId: userId,
        habitId: habitId,
        scheduleType: draft.scheduleType,
        scheduleConfig: config,
      );
      draft.scheduleId = created.id;
    } else {
      await schedules.update(
        userId: userId,
        id: draft.scheduleId!,
        habitId: habitId,
        scheduleType: draft.scheduleType,
        scheduleConfig: config,
      );
    }
    for (final extra in existing.skip(1)) {
      await schedules.delete(userId, extra.id);
    }
  }

  Future<void> _saveRules(
    String userId,
    String habitId,
    List<PointRuleDraft> drafts,
  ) async {
    final existing = await rules.listForHabit(userId, habitId);
    final keptIds = drafts.map((item) => item.id).whereType<String>().toSet();
    for (final row in existing.where((item) => !keptIds.contains(item.id))) {
      await rules.archive(userId, row.id);
    }
    for (var index = 0; index < drafts.length; index++) {
      final draft = drafts[index];
      final min = draft.operator == PointRuleOperator.completed
          ? null
          : double.parse(draft.valueMin.trim());
      final max = draft.operator == PointRuleOperator.between
          ? double.parse(draft.valueMax.trim())
          : null;
      final points = int.parse(draft.points.trim());
      if (draft.id == null) {
        final created = await rules.create(
          userId: userId,
          habitId: habitId,
          operator: draft.operator,
          valueMin: min,
          valueMax: max,
          points: points,
          sortOrder: index,
        );
        draft.id = created.id;
      } else {
        await rules.update(
          userId: userId,
          id: draft.id!,
          habitId: habitId,
          operator: draft.operator,
          valueMin: min,
          valueMax: max,
          points: points,
          sortOrder: index,
        );
      }
    }
  }

  Future<void> _savePauses(
    String userId,
    String habitId,
    List<HabitPauseDraft> drafts,
  ) async {
    final existing = await pauses.listForHabit(userId, habitId);
    final keptIds = drafts.map((item) => item.id).whereType<String>().toSet();
    for (final row in existing.where((item) => !keptIds.contains(item.id))) {
      await pauses.delete(userId, row.id);
    }
    for (final draft in drafts) {
      if (draft.id == null) {
        final created = await pauses.create(
          userId: userId,
          habitId: habitId,
          startDate: draft.startDate,
          endDate: draft.endDate,
        );
        draft.id = created.id;
      } else {
        await pauses.update(
          userId: userId,
          id: draft.id!,
          habitId: habitId,
          startDate: draft.startDate,
          endDate: draft.endDate,
        );
      }
    }
  }

  Future<void> _saveReminder(
    String userId,
    String habitId,
    HabitDraft draft,
  ) async {
    final existing = await reminders.getForHabit(userId, habitId);
    if (existing == null) {
      if (draft.reminderEnabled) {
        final created = await reminders.create(
          userId: userId,
          habitId: habitId,
          enabled: true,
          timeOfDay: draft.reminderTime,
        );
        draft.reminderId = created.id;
      }
      return;
    }
    await reminders.update(
      userId: userId,
      id: existing.id,
      enabled: draft.reminderEnabled,
      timeOfDay: draft.reminderTime,
    );
  }
}

class HabitCatalog {
  const HabitCatalog({required this.habits, required this.categories});

  final List<HabitListEntry> habits;
  final List<CategoryChoice> categories;
}

class HabitListEntry {
  const HabitListEntry({
    required this.id,
    required this.name,
    required this.measurementType,
    required this.scheduleSummary,
    required this.currentStreak,
    required this.archived,
    this.categoryName,
    this.reminderTime,
  });

  final String id;
  final String name;
  final String? categoryName;
  final MeasurementType measurementType;
  final String scheduleSummary;
  final String? reminderTime;
  final int currentStreak;
  final bool archived;
}

class CategoryChoice {
  const CategoryChoice({required this.id, required this.name});

  final String id;
  final String name;
}

class HabitDraft {
  HabitDraft({
    this.id,
    this.name = '',
    this.categoryId,
    this.measurementType = MeasurementType.yesNo,
    this.scheduleId,
    this.scheduleType = ScheduleType.daily,
    Set<int>? scheduleDays,
    this.timesPerWeek = 3,
    List<DateTime>? customDates,
    List<HabitOptionDraft>? options,
    List<PointRuleDraft>? rules,
    List<HabitPauseDraft>? pauses,
    this.missedPenaltyEnabled = false,
    this.missedPenaltyPoints = '0',
    this.reminderEnabled = false,
    this.reminderTime = '08:00',
    this.reminderId,
  }) : scheduleDays = scheduleDays ?? {DateTime.monday},
       customDates = customDates ?? [],
       options = options ?? [],
       rules = rules ?? [],
       pauses = pauses ?? [];

  String? id;
  String name;
  String? categoryId;
  MeasurementType measurementType;
  String? scheduleId;
  ScheduleType scheduleType;
  Set<int> scheduleDays;
  int timesPerWeek;
  List<DateTime> customDates;
  List<HabitOptionDraft> options;
  List<PointRuleDraft> rules;
  List<HabitPauseDraft> pauses;
  bool missedPenaltyEnabled;
  String missedPenaltyPoints;
  bool reminderEnabled;
  String reminderTime;
  String? reminderId;

  String get scheduleConfig => switch (scheduleType) {
    ScheduleType.daily => '{}',
    ScheduleType.specificDays => jsonEncode({
      'days': scheduleDays.toList()..sort(),
    }),
    ScheduleType.timesPerWeek => jsonEncode({'times': timesPerWeek}),
    ScheduleType.custom => jsonEncode({
      'dates': customDates.map(habitDateKey).toList()..sort(),
    }),
  };

  String? validate() {
    if (name.trim().isEmpty) return 'Enter a habit name.';
    if (scheduleType == ScheduleType.specificDays && scheduleDays.isEmpty) {
      return 'Choose at least one scheduled day.';
    }
    if (scheduleType == ScheduleType.custom && customDates.isEmpty) {
      return 'Add at least one custom date.';
    }
    for (final option in options) {
      if (option.label.trim().isEmpty) return 'Every option needs a label.';
      if (option.numericValue.trim().isNotEmpty &&
          double.tryParse(option.numericValue.trim()) == null) {
        return 'Option values must be valid numbers.';
      }
    }
    for (final rule in rules) {
      final error = rule.validate();
      if (error != null) return error;
    }
    if (missedPenaltyEnabled) {
      final points = int.tryParse(missedPenaltyPoints.trim());
      if (points == null || points > 0) {
        return 'Missed penalty must be zero or a negative whole number.';
      }
    }
    for (final pause in pauses) {
      if (pause.endDate.isBefore(pause.startDate)) {
        return 'A pause end date cannot be before its start date.';
      }
    }
    for (var left = 0; left < pauses.length; left++) {
      for (var right = left + 1; right < pauses.length; right++) {
        final a = pauses[left];
        final b = pauses[right];
        if (!a.endDate.isBefore(b.startDate) &&
            !b.endDate.isBefore(a.startDate)) {
          return 'Pause date ranges cannot overlap.';
        }
      }
    }
    if (reminderEnabled &&
        !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(reminderTime)) {
      return 'Choose a valid reminder time.';
    }
    return null;
  }
}

class HabitOptionDraft {
  HabitOptionDraft({this.id, this.label = '', this.numericValue = ''});

  String? id;
  String label;
  String numericValue;
}

class PointRuleDraft {
  PointRuleDraft({
    this.id,
    this.operator = PointRuleOperator.completed,
    this.valueMin = '',
    this.valueMax = '',
    this.points = '',
  });

  String? id;
  PointRuleOperator operator;
  String valueMin;
  String valueMax;
  String points;

  String? validate() {
    if (int.tryParse(points.trim()) == null) {
      return 'Every point rule needs whole-number points.';
    }
    final min = double.tryParse(valueMin.trim());
    final max = double.tryParse(valueMax.trim());
    switch (operator) {
      case PointRuleOperator.completed:
        return null;
      case PointRuleOperator.between:
        if (min == null || max == null || min > max) {
          return 'Between rules need a valid minimum and maximum.';
        }
      case PointRuleOperator.eq:
      case PointRuleOperator.lt:
      case PointRuleOperator.lte:
      case PointRuleOperator.gt:
      case PointRuleOperator.gte:
        if (min == null) return 'This point rule needs a comparison value.';
    }
    return null;
  }
}

class HabitPauseDraft {
  HabitPauseDraft({this.id, required this.startDate, required this.endDate});

  String? id;
  DateTime startDate;
  DateTime endDate;
}

String _scheduleSummary(HabitSchedule schedule) {
  final config = jsonDecode(schedule.scheduleConfig);
  final map = config is Map<String, dynamic> ? config : <String, dynamic>{};
  return switch (schedule.scheduleType) {
    ScheduleType.daily => 'Daily',
    ScheduleType.specificDays => _weekdaySummary(
      ((map['days'] as List?) ?? const []).whereType<int>(),
    ),
    ScheduleType.timesPerWeek => '${map['times'] ?? '?'} times per week',
    ScheduleType.custom =>
      '${((map['dates'] as List?) ?? const []).length} custom dates',
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
