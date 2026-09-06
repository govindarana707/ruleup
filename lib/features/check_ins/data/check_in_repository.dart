import 'package:drift/drift.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/database/habit_date_converter.dart';
import 'package:ruleup/core/sync/sync_service.dart';
import 'package:ruleup/core/utils/habit_date.dart';
import 'package:ruleup/features/points/data/point_ledger_repository.dart';
import 'package:ruleup/features/habits/domain/schedule_applicability.dart';
import 'package:ruleup/features/points/domain/point_rule_evaluator.dart';

class CheckInRepository {
  CheckInRepository(
    this._database,
    this._sync, {
    PointLedgerRepository? pointLedger,
    PointRuleEvaluator? evaluator,
    DateTime Function()? now,
  }) : _pointLedger = pointLedger ?? PointLedgerRepository(_database, _sync),
       _evaluator = evaluator ?? const PointRuleEvaluator(),
       _now = now ?? DateTime.now;

  final AppDatabase _database;
  final SyncService _sync;
  final PointLedgerRepository _pointLedger;
  final PointRuleEvaluator _evaluator;
  final ScheduleApplicability _applicability = const ScheduleApplicability();
  final DateTime Function() _now;

  Future<CheckIn> create({
    required String userId,
    required String habitId,
    required DateTime habitDate,
    String? optionId,
    double? measuredValue,
    String? note,
  }) => _database.transaction(() async {
    _validateMeasuredValue(measuredValue);
    final normalizedDate = normalizeHabitDate(habitDate);
    if (await getForHabitDate(userId, habitId, normalizedDate) != null) {
      throw DuplicateCheckInException(habitId, normalizedDate);
    }

    final habit = await _verifyHabit(userId, habitId);
    final option = await _verifyOption(userId, habitId, optionId);
    final evaluation = await _evaluateIfApplicable(
      userId: userId,
      habit: habit,
      habitDate: normalizedDate,
      measuredValue: measuredValue ?? option?.numericValue,
    );
    final checkedInAt = _now().toUtc();
    final checkIn = await _database
        .into(_database.checkIns)
        .insertReturning(
          CheckInsCompanion.insert(
            userId: userId,
            habitId: habitId,
            habitDate: normalizedDate,
            optionId: Value(optionId),
            measuredValue: Value(measuredValue),
            note: Value(_normalizeNote(note)),
            awardedPoints: evaluation.points,
            matchedRuleId: Value(evaluation.matchedRule?.id),
            checkedInAt: checkedInAt,
            editableUntil: normalizedDate.add(const Duration(hours: 36)),
          ),
        );
    await _enqueue(checkIn, 'create');
    await _pointLedger.reconcileCheckIn(userId: userId, checkInId: checkIn.id);
    return checkIn;
  });

  Future<CheckIn?> getById(String userId, String id) {
    final query = _database.select(_database.checkIns)
      ..where((row) => row.id.equals(id) & row.userId.equals(userId));
    return query.getSingleOrNull();
  }

  Future<CheckIn?> getForHabitDate(
    String userId,
    String habitId,
    DateTime habitDate,
  ) {
    final normalizedDate = normalizeHabitDate(habitDate);
    final query = _database.select(_database.checkIns)
      ..where(
        (row) =>
            row.userId.equals(userId) &
            row.habitId.equals(habitId) &
            row.habitDate.equals(
              const HabitDateConverter().toSql(normalizedDate),
            ),
      );
    return query.getSingleOrNull();
  }

  Future<List<CheckIn>> listForDate(String userId, DateTime habitDate) {
    final normalizedDate = normalizeHabitDate(habitDate);
    final query = _database.select(_database.checkIns)
      ..where(
        (row) =>
            row.userId.equals(userId) &
            row.habitDate.equals(
              const HabitDateConverter().toSql(normalizedDate),
            ),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.checkedInAt),
        (row) => OrderingTerm.asc(row.id),
      ]);
    return query.get();
  }

  Future<List<CheckIn>> listForHabit(String userId, String habitId) {
    final query = _database.select(_database.checkIns)
      ..where((row) => row.userId.equals(userId) & row.habitId.equals(habitId))
      ..orderBy([
        (row) => OrderingTerm.asc(row.habitDate),
        (row) => OrderingTerm.asc(row.checkedInAt),
      ]);
    return query.get();
  }

  Future<CheckIn?> update({
    required String userId,
    required String id,
    required String? optionId,
    required double? measuredValue,
    required String? note,
  }) => _database.transaction(() async {
    _validateMeasuredValue(measuredValue);
    final existing = await getById(userId, id);
    if (existing == null) return null;
    final now = _now().toUtc();
    if (now.isAfter(existing.editableUntil)) {
      throw CheckInLockedException(existing.editableUntil);
    }

    final habit = await _verifyHabit(userId, existing.habitId);
    final option = await _verifyOption(userId, habit.id, optionId);
    final evaluation = await _evaluateIfApplicable(
      userId: userId,
      habit: habit,
      habitDate: existing.habitDate,
      measuredValue: measuredValue ?? option?.numericValue,
    );
    await (_database.update(
      _database.checkIns,
    )..where((row) => row.id.equals(id) & row.userId.equals(userId))).write(
      CheckInsCompanion(
        optionId: Value(optionId),
        measuredValue: Value(measuredValue),
        note: Value(_normalizeNote(note)),
        awardedPoints: Value(evaluation.points),
        matchedRuleId: Value(evaluation.matchedRule?.id),
        updatedAt: Value(now),
      ),
    );
    final updated = await getById(userId, id);
    await _enqueue(updated!, 'update');
    await _pointLedger.reconcileCheckIn(userId: userId, checkInId: updated.id);
    return updated;
  });

  Future<Habit> _verifyHabit(String userId, String habitId) async {
    final habit =
        await (_database.select(_database.habits)..where(
              (row) => row.id.equals(habitId) & row.userId.equals(userId),
            ))
            .getSingleOrNull();
    if (habit == null) throw ArgumentError.value(habitId, 'habitId');
    return habit;
  }

  Future<HabitOption?> _verifyOption(
    String userId,
    String habitId,
    String? optionId,
  ) async {
    if (optionId == null) return null;
    final option =
        await (_database.select(_database.habitOptions)..where(
              (row) =>
                  row.id.equals(optionId) &
                  row.userId.equals(userId) &
                  row.habitId.equals(habitId),
            ))
            .getSingleOrNull();
    if (option == null) throw ArgumentError.value(optionId, 'optionId');
    return option;
  }

  Future<PointRuleEvaluation> _evaluate({
    required String userId,
    required Habit habit,
    required double? measuredValue,
  }) async {
    final storedRules =
        await (_database.select(_database.pointRules)..where(
              (row) => row.userId.equals(userId) & row.habitId.equals(habit.id),
            ))
            .get();
    return _evaluator.evaluate(
      measurementType: habit.measurementType,
      measuredValue: measuredValue,
      completed: true,
      rules: storedRules.map(
        (rule) => PointRuleDefinition(
          id: rule.id,
          operator: rule.operator,
          valueMin: rule.valueMin,
          valueMax: rule.valueMax,
          points: rule.points,
          sortOrder: rule.sortOrder,
          archivedAt: rule.archivedAt,
        ),
      ),
    );
  }

  Future<PointRuleEvaluation> _evaluateIfApplicable({
    required String userId,
    required Habit habit,
    required DateTime habitDate,
    required double? measuredValue,
  }) async {
    final dateValue = const HabitDateConverter().toSql(habitDate);
    final pause =
        await (_database.select(_database.habitPauses)
              ..where(
                (row) =>
                    row.userId.equals(userId) &
                    row.habitId.equals(habit.id) &
                    row.startDate.isSmallerOrEqualValue(dateValue) &
                    row.endDate.isBiggerOrEqualValue(dateValue),
              )
              ..limit(1))
            .getSingleOrNull();
    if (pause != null) return const PointRuleEvaluation.noMatch();

    final storedSchedules =
        await (_database.select(_database.habitSchedules)..where(
              (row) => row.userId.equals(userId) & row.habitId.equals(habit.id),
            ))
            .get();
    final schedules = storedSchedules.map(
      (schedule) => HabitScheduleDefinition.fromConfig(
        type: schedule.scheduleType,
        scheduleConfig: schedule.scheduleConfig,
      ),
    );
    if (!_applicability.isApplicable(
      habitDate: habitDate,
      schedules: schedules,
    )) {
      return const PointRuleEvaluation.noMatch();
    }
    return _evaluate(
      userId: userId,
      habit: habit,
      measuredValue: measuredValue,
    );
  }

  void _validateMeasuredValue(double? measuredValue) {
    if (measuredValue != null && !measuredValue.isFinite) {
      throw ArgumentError.value(
        measuredValue,
        'measuredValue',
        'Must be finite',
      );
    }
  }

  String? _normalizeNote(String? note) {
    final normalized = note?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  Future<void> _enqueue(CheckIn checkIn, String operation) => _sync.enqueue(
    userId: checkIn.userId,
    entityType: 'check_in',
    entityId: checkIn.id,
    operation: operation,
  );
}

class DuplicateCheckInException implements Exception {
  const DuplicateCheckInException(this.habitId, this.habitDate);

  final String habitId;
  final DateTime habitDate;
}

class CheckInLockedException implements Exception {
  const CheckInLockedException(this.editableUntil);

  final DateTime editableUntil;
}
