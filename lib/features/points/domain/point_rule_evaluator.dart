import 'package:ruleup/features/habits/domain/measurement_type.dart';
import 'package:ruleup/features/points/domain/point_rule_operator.dart';

class PointRuleDefinition {
  const PointRuleDefinition({
    required this.id,
    required this.operator,
    required this.points,
    this.valueMin,
    this.valueMax,
    this.sortOrder = 0,
    this.archivedAt,
  });

  final String id;
  final PointRuleOperator operator;
  final double? valueMin;
  final double? valueMax;
  final int points;
  final int sortOrder;
  final DateTime? archivedAt;
}

class PointRuleEvaluation {
  const PointRuleEvaluation._({
    required this.matchedRule,
    required this.points,
  });

  const PointRuleEvaluation.noMatch() : this._(matchedRule: null, points: 0);

  factory PointRuleEvaluation.match(PointRuleDefinition rule) {
    return PointRuleEvaluation._(matchedRule: rule, points: rule.points);
  }

  final PointRuleDefinition? matchedRule;
  final int points;

  bool get hasMatch => matchedRule != null;
}

class PointRuleEvaluator {
  const PointRuleEvaluator();

  PointRuleEvaluation evaluate({
    required MeasurementType measurementType,
    required Iterable<PointRuleDefinition> rules,
    double? measuredValue,
    bool completed = false,
  }) {
    final matches = rules
        .where((rule) => rule.archivedAt == null)
        .where(
          (rule) => _matches(
            rule,
            measurementType: measurementType,
            measuredValue: measuredValue,
            completed: completed,
          ),
        )
        .toList();

    if (matches.isEmpty) return const PointRuleEvaluation.noMatch();
    matches.sort(_compareMatches);
    return PointRuleEvaluation.match(matches.first);
  }

  bool _matches(
    PointRuleDefinition rule, {
    required MeasurementType measurementType,
    required double? measuredValue,
    required bool completed,
  }) {
    if (rule.operator == PointRuleOperator.completed) return completed;
    if (measurementType == MeasurementType.yesNo ||
        measuredValue == null ||
        !measuredValue.isFinite) {
      return false;
    }

    final min = rule.valueMin;
    final max = rule.valueMax;
    return switch (rule.operator) {
      PointRuleOperator.completed => completed,
      PointRuleOperator.eq => min != null && measuredValue == min,
      PointRuleOperator.lt => min != null && measuredValue < min,
      PointRuleOperator.lte => min != null && measuredValue <= min,
      PointRuleOperator.gt => min != null && measuredValue > min,
      PointRuleOperator.gte => min != null && measuredValue >= min,
      PointRuleOperator.between =>
        min != null &&
            max != null &&
            min <= max &&
            measuredValue >= min &&
            measuredValue <= max,
    };
  }

  int _compareMatches(PointRuleDefinition left, PointRuleDefinition right) {
    final groupOrder = _matchGroup(left.points)
        .compareTo(_matchGroup(right.points));
    if (groupOrder != 0) return groupOrder;

    final pointsOrder = left.points > 0
        ? right.points.compareTo(left.points)
        : left.points < 0
        ? left.points.compareTo(right.points)
        : 0;
    if (pointsOrder != 0) return pointsOrder;

    final sortOrder = left.sortOrder.compareTo(right.sortOrder);
    if (sortOrder != 0) return sortOrder;
    return left.id.compareTo(right.id);
  }

  int _matchGroup(int points) {
    if (points > 0) return 0;
    if (points < 0) return 1;
    return 2;
  }
}
