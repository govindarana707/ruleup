import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/features/habits/domain/measurement_type.dart';
import 'package:ruleup/features/points/domain/point_rule_evaluator.dart';
import 'package:ruleup/features/points/domain/point_rule_operator.dart';

void main() {
  const evaluator = PointRuleEvaluator();

  test('selects the applicable smoking penalty tier', () {
    final result = evaluator.evaluate(
      measurementType: MeasurementType.count,
      measuredValue: 8,
      completed: true,
      rules: const [
        PointRuleDefinition(
          id: 'low-smoking',
          operator: PointRuleOperator.between,
          valueMin: 1,
          valueMax: 5,
          points: -1,
        ),
        PointRuleDefinition(
          id: 'medium-smoking',
          operator: PointRuleOperator.between,
          valueMin: 6,
          valueMax: 10,
          points: -3,
        ),
        PointRuleDefinition(
          id: 'high-smoking',
          operator: PointRuleOperator.gt,
          valueMin: 10,
          points: -5,
        ),
      ],
    );

    expect(result.matchedRule?.id, 'medium-smoking');
    expect(result.points, -3);
  });

  test('selects the highest applicable study duration reward', () {
    final result = evaluator.evaluate(
      measurementType: MeasurementType.duration,
      measuredValue: 90,
      completed: true,
      rules: const [
        PointRuleDefinition(
          id: 'study-30',
          operator: PointRuleOperator.gte,
          valueMin: 30,
          points: 5,
        ),
        PointRuleDefinition(
          id: 'study-60',
          operator: PointRuleOperator.gte,
          valueMin: 60,
          points: 10,
        ),
        PointRuleDefinition(
          id: 'study-120',
          operator: PointRuleOperator.gte,
          valueMin: 120,
          points: 20,
        ),
      ],
    );

    expect(result.matchedRule?.id, 'study-60');
    expect(result.points, 10);
  });

  test('completed rule matches only a completed input', () {
    const rule = PointRuleDefinition(
      id: 'completed',
      operator: PointRuleOperator.completed,
      points: 4,
    );

    final completed = evaluator.evaluate(
      measurementType: MeasurementType.yesNo,
      completed: true,
      rules: const [rule],
    );
    final incomplete = evaluator.evaluate(
      measurementType: MeasurementType.yesNo,
      rules: const [rule],
    );

    expect(completed.matchedRule?.id, 'completed');
    expect(completed.points, 4);
    expect(incomplete.hasMatch, isFalse);
    expect(incomplete.points, 0);
  });

  test('between includes both boundaries', () {
    const rule = PointRuleDefinition(
      id: 'range',
      operator: PointRuleOperator.between,
      valueMin: 5,
      valueMax: 10,
      points: 3,
    );

    for (final boundary in [5.0, 10.0]) {
      final result = evaluator.evaluate(
        measurementType: MeasurementType.value,
        measuredValue: boundary,
        rules: const [rule],
      );
      expect(result.matchedRule?.id, 'range');
    }
  });

  test('supports exact and strict numeric comparisons', () {
    final equal = evaluator.evaluate(
      measurementType: MeasurementType.value,
      measuredValue: 5,
      rules: const [
        PointRuleDefinition(
          id: 'equal',
          operator: PointRuleOperator.eq,
          valueMin: 5,
          points: 1,
        ),
      ],
    );
    final less = evaluator.evaluate(
      measurementType: MeasurementType.value,
      measuredValue: 4,
      rules: const [
        PointRuleDefinition(
          id: 'less',
          operator: PointRuleOperator.lt,
          valueMin: 5,
          points: 2,
        ),
      ],
    );
    final lessAtBoundary = evaluator.evaluate(
      measurementType: MeasurementType.value,
      measuredValue: 5,
      rules: const [
        PointRuleDefinition(
          id: 'less',
          operator: PointRuleOperator.lt,
          valueMin: 5,
          points: 2,
        ),
      ],
    );
    final lessOrEqual = evaluator.evaluate(
      measurementType: MeasurementType.value,
      measuredValue: 5,
      rules: const [
        PointRuleDefinition(
          id: 'less-or-equal',
          operator: PointRuleOperator.lte,
          valueMin: 5,
          points: 3,
        ),
      ],
    );

    expect(equal.matchedRule?.id, 'equal');
    expect(less.matchedRule?.id, 'less');
    expect(lessAtBoundary.hasMatch, isFalse);
    expect(lessOrEqual.matchedRule?.id, 'less-or-equal');
  });

  test('returns zero and no rule when nothing matches', () {
    final result = evaluator.evaluate(
      measurementType: MeasurementType.count,
      measuredValue: 2,
      rules: const [
        PointRuleDefinition(
          id: 'minimum',
          operator: PointRuleOperator.gte,
          valueMin: 5,
          points: 8,
        ),
      ],
    );

    expect(result.hasMatch, isFalse);
    expect(result.matchedRule, isNull);
    expect(result.points, 0);
  });

  test('overlapping rewards never stack and highest reward wins', () {
    final result = evaluator.evaluate(
      measurementType: MeasurementType.duration,
      measuredValue: 75,
      rules: const [
        PointRuleDefinition(
          id: 'base',
          operator: PointRuleOperator.gte,
          valueMin: 30,
          points: 4,
        ),
        PointRuleDefinition(
          id: 'bonus',
          operator: PointRuleOperator.gte,
          valueMin: 60,
          points: 9,
        ),
      ],
    );

    expect(result.matchedRule?.id, 'bonus');
    expect(result.points, 9);
  });

  test('overlapping penalties select the strongest negative points', () {
    final result = evaluator.evaluate(
      measurementType: MeasurementType.count,
      measuredValue: 12,
      rules: const [
        PointRuleDefinition(
          id: 'penalty',
          operator: PointRuleOperator.gt,
          valueMin: 0,
          points: -2,
        ),
        PointRuleDefinition(
          id: 'strong-penalty',
          operator: PointRuleOperator.gte,
          valueMin: 10,
          points: -5,
        ),
      ],
    );

    expect(result.matchedRule?.id, 'strong-penalty');
    expect(result.points, -5);
  });

  test('archived rules never evaluate', () {
    final result = evaluator.evaluate(
      measurementType: MeasurementType.value,
      measuredValue: 10,
      rules: [
        PointRuleDefinition(
          id: 'archived',
          operator: PointRuleOperator.gte,
          valueMin: 1,
          points: 100,
          archivedAt: DateTime.utc(2026),
        ),
        const PointRuleDefinition(
          id: 'active',
          operator: PointRuleOperator.gte,
          valueMin: 1,
          points: 5,
        ),
      ],
    );

    expect(result.matchedRule?.id, 'active');
    expect(result.points, 5);
  });

  test('equal-point ties use sort order then rule id deterministically', () {
    const rules = [
      PointRuleDefinition(
        id: 'z-rule',
        operator: PointRuleOperator.gte,
        valueMin: 1,
        points: 5,
        sortOrder: 0,
      ),
      PointRuleDefinition(
        id: 'b-rule',
        operator: PointRuleOperator.gte,
        valueMin: 1,
        points: 5,
        sortOrder: -1,
      ),
      PointRuleDefinition(
        id: 'a-rule',
        operator: PointRuleOperator.gte,
        valueMin: 1,
        points: 5,
        sortOrder: -1,
      ),
    ];

    for (final orderedRules in [rules, rules.reversed]) {
      final result = evaluator.evaluate(
        measurementType: MeasurementType.value,
        measuredValue: 2,
        rules: orderedRules,
      );
      expect(result.matchedRule?.id, 'a-rule');
    }
  });
}
