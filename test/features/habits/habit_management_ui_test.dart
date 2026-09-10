import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/habits/domain/measurement_type.dart';
import 'package:ruleup/features/habits/presentation/habit_editor_screen.dart';
import 'package:ruleup/features/habits/presentation/habit_list_screen.dart';
import 'package:ruleup/features/habits/presentation/habit_management_provider.dart';
import 'package:ruleup/features/points/domain/point_rule_operator.dart';

void main() {
  testWidgets('habit list shows management details and empty archived state', (
    tester,
  ) async {
    await _pumpList(tester, catalog: _catalog);

    expect(find.text('Habits'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.byKey(const Key('create-habit-button')), findsOneWidget);
    expect(find.text('Morning walk'), findsOneWidget);
    expect(find.text('Wellbeing'), findsOneWidget);
    expect(find.text('Duration'), findsOneWidget);
    expect(find.text('Mon, Wed, Fri'), findsOneWidget);
    expect(find.text('07:30'), findsOneWidget);
    expect(find.text('6d'), findsOneWidget);
    expect(find.text('6 day streak'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);

    await tester.tap(find.text('Archived'));
    await tester.pump();
    expect(find.text('No archived habits'), findsOneWidget);
  });

  testWidgets('create flow validates and saves a complete draft', (
    tester,
  ) async {
    HabitDraft? savedDraft;
    await _pumpList(
      tester,
      catalog: const HabitCatalog(habits: [], categories: []),
      save: (userId, draft) async {
        savedDraft = draft;
        return 'new-habit';
      },
    );

    await tester.tap(find.byKey(const Key('create-habit-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('habit-editor-screen')), findsOneWidget);
    expect(find.text('Habit options'), findsOneWidget);
    expect(find.text('Schedule'), findsOneWidget);

    await tester.tap(find.byKey(const Key('save-habit-button')));
    await tester.pump();
    expect(find.text('Enter a habit name.'), findsWidgets);

    await tester.enterText(
      find.byKey(const Key('habit-name-field')),
      'Read nightly',
    );
    await tester.tap(find.byKey(const Key('save-habit-button')));
    await tester.pumpAndSettle();

    expect(savedDraft?.name, 'Read nightly');
    expect(savedDraft?.measurementType, MeasurementType.yesNo);
    expect(find.byKey(const Key('habit-list-screen')), findsOneWidget);
  });

  testWidgets('edit flow loads and persists the selected habit', (
    tester,
  ) async {
    HabitDraft? savedDraft;
    await _pumpList(
      tester,
      catalog: _catalog,
      load: (userId, habitId) async => HabitDraft(
        id: habitId,
        name: 'Morning walk',
        categoryId: 'category-1',
        measurementType: MeasurementType.duration,
      ),
      save: (userId, draft) async {
        savedDraft = draft;
        return draft.id!;
      },
    );

    await tester.tap(find.byKey(const Key('habit-tile-habit-1')));
    await tester.pumpAndSettle();
    expect(find.text('Edit habit'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('habit-name-field')),
      'Long morning walk',
    );
    await tester.tap(find.byKey(const Key('save-habit-button')));
    await tester.pumpAndSettle();

    expect(savedDraft?.id, 'habit-1');
    expect(savedDraft?.name, 'Long morning walk');
  });

  testWidgets('count habits expose clear point rules and Smoking reference', (
    tester,
  ) async {
    HabitDraft? savedDraft;
    await _pumpEditor(
      tester,
      save: (userId, draft) async {
        savedDraft = draft;
        return 'smoking-habit';
      },
    );

    await tester.enterText(
      find.byKey(const Key('habit-name-field')),
      'Smoking',
    );
    await tester.tap(find.byKey(const Key('measurement-type-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Count').last);
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Point Rules'),
      find.byKey(const Key('habit-editor-scroll')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(find.text('Points'), findsOneWidget);
    expect(find.text('Best Match Only'), findsOneWidget);
    expect(find.text('Smoking example'), findsOneWidget);
    expect(find.text('≤ 10 cigarettes → +1 point'), findsOneWidget);
    expect(find.text('≤ 5 cigarettes → +2 points'), findsOneWidget);
    expect(find.text('≤ 1 cigarette → +4 points'), findsOneWidget);
    expect(find.text('= 0 cigarettes → +5 points'), findsOneWidget);
    expect(
      find.text(
        '4 cigarettes earns +2 points only — the +1 rule does not stack.',
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byKey(const Key('add-rule-button')));
    await tester.tap(find.byKey(const Key('add-rule-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rule-operator-field')));
    await tester.pumpAndSettle();
    for (final label in [
      'Completed',
      '= Equals',
      '< Less than',
      '≤ Less than or equal',
      '> Greater than',
      '≥ Greater than or equal',
      'Between (inclusive)',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    await tester.tap(find.text('≤ Less than or equal').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('rule-value-min-field')), '10');
    await tester.enterText(find.byKey(const Key('rule-points-field')), '1');
    await tester.pump();
    expect(find.text('Preview: ≤ 10 → +1 point'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-rule-button')));
    await tester.pumpAndSettle();

    expect(find.text('≤ 10 → +1 point'), findsOneWidget);
    await tester.tap(find.byKey(const Key('save-habit-button')));
    await tester.pumpAndSettle();

    expect(savedDraft?.name, 'Smoking');
    expect(savedDraft?.measurementType, MeasurementType.count);
    expect(savedDraft?.rules, hasLength(1));
    expect(savedDraft?.rules.single.operator, PointRuleOperator.lte);
    expect(savedDraft?.rules.single.valueMin, '10');
    expect(savedDraft?.rules.single.points, '1');
  });

  testWidgets('point rules can be edited, deleted, and reordered', (
    tester,
  ) async {
    HabitDraft? savedDraft;
    await _pumpEditor(
      tester,
      habitId: 'habit-1',
      load: (userId, habitId) async => HabitDraft(
        id: habitId,
        name: 'Smoking',
        measurementType: MeasurementType.count,
        rules: [
          PointRuleDraft(
            id: 'positive',
            operator: PointRuleOperator.lte,
            valueMin: '10',
            points: '1',
          ),
          PointRuleDraft(
            id: 'negative',
            operator: PointRuleOperator.gt,
            valueMin: '10',
            points: '-2',
          ),
          PointRuleDraft(
            id: 'zero',
            operator: PointRuleOperator.between,
            valueMin: '6',
            valueMax: '9',
            points: '0',
          ),
        ],
      ),
      save: (userId, draft) async {
        savedDraft = draft;
        return draft.id!;
      },
    );

    await tester.dragUntilVisible(
      find.text('≤ 10 → +1 point'),
      find.byKey(const Key('habit-editor-scroll')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(find.text('> 10 → -2 points'), findsOneWidget);
    expect(find.text('Between 6 and 9 → 0 points'), findsOneWidget);

    await tester.tap(find.text('Edit').at(1));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('rule-points-field')), '-4');
    await tester.tap(find.byKey(const Key('confirm-rule-button')));
    await tester.pumpAndSettle();
    expect(find.text('> 10 → -4 points'), findsOneWidget);

    await tester.tap(find.byTooltip('Move rule up').last);
    await tester.pump();
    await tester.tap(find.byTooltip('Delete point rule').first);
    await tester.pump();
    await tester.tap(find.byKey(const Key('save-habit-button')));
    await tester.pumpAndSettle();

    expect(savedDraft?.rules.map((rule) => rule.id), ['zero', 'negative']);
    expect(savedDraft?.rules.last.points, '-4');
  });

  testWidgets('archive confirmation and restore call scoped actions', (
    tester,
  ) async {
    String? archived;
    String? restored;
    await _pumpList(
      tester,
      catalog: _catalog,
      archive: (userId, habitId) async => archived = '$userId/$habitId',
      restore: (userId, habitId) async => restored = '$userId/$habitId',
    );

    await tester.tap(find.byTooltip('Habit actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('Archive habit?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-archive-button')));
    await tester.pumpAndSettle();
    expect(archived, 'user-1/habit-1');

    await _pumpList(
      tester,
      catalog: _archivedCatalog,
      restore: (userId, habitId) async {
        restored = '$userId/$habitId';
      },
    );
    await tester.tap(find.text('Archived'));
    await tester.pump();
    await tester.tap(find.byTooltip('Habit actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(restored, 'user-1/habit-1');
  });

  testWidgets('habit list renders loading, error, and offline states', (
    tester,
  ) async {
    final pending = Completer<HabitCatalog>();
    await _pumpList(tester, catalogFuture: pending.future, settle: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await _pumpList(tester, catalogError: Exception('database unavailable'));
    expect(find.text("Couldn't load your habits"), findsOneWidget);

    await _pumpList(
      tester,
      catalog: const HabitCatalog(habits: [], categories: []),
      offline: true,
    );
    expect(find.textContaining('Offline'), findsOneWidget);
  });
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  String? habitId,
  HabitDraftLoader? load,
  required HabitSaveAction save,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        habitDraftLoaderProvider.overrideWithValue(
          load ?? (userId, habitId) async => HabitDraft(id: habitId),
        ),
        habitSaveActionProvider.overrideWithValue(save),
        categoryCreateActionProvider.overrideWithValue(
          (userId, name) async =>
              CategoryChoice(id: 'new-category', name: name),
        ),
      ],
      child: MaterialApp(
        home: HabitEditorScreen(
          userId: 'user-1',
          habitId: habitId,
          initialCategories: const [],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpList(
  WidgetTester tester, {
  HabitCatalog? catalog,
  Future<HabitCatalog>? catalogFuture,
  Object? catalogError,
  HabitDraftLoader? load,
  HabitSaveAction? save,
  HabitMutationAction? archive,
  HabitMutationAction? restore,
  bool offline = false,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        backendHealthProvider.overrideWith((ref) async {
          if (offline) throw Exception('offline');
        }),
        habitCatalogProvider.overrideWith((ref, _) async {
          if (catalogError != null) throw catalogError;
          if (catalogFuture != null) return catalogFuture;
          return catalog!;
        }),
        habitDraftLoaderProvider.overrideWithValue(
          load ?? (userId, habitId) async => HabitDraft(id: habitId),
        ),
        habitSaveActionProvider.overrideWithValue(
          save ?? (userId, draft) async => draft.id ?? 'new-habit',
        ),
        habitArchiveActionProvider.overrideWithValue(
          archive ?? (userId, habitId) async {},
        ),
        habitRestoreActionProvider.overrideWithValue(
          restore ?? (userId, habitId) async {},
        ),
        categoryCreateActionProvider.overrideWithValue(
          (userId, name) async =>
              CategoryChoice(id: 'new-category', name: name),
        ),
      ],
      child: const MaterialApp(home: HabitListScreen(userId: 'user-1')),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

const _catalog = HabitCatalog(
  categories: [CategoryChoice(id: 'category-1', name: 'Wellbeing')],
  habits: [
    HabitListEntry(
      id: 'habit-1',
      name: 'Morning walk',
      categoryName: 'Wellbeing',
      measurementType: MeasurementType.duration,
      scheduleSummary: 'Mon, Wed, Fri',
      reminderTime: '07:30',
      currentStreak: 6,
      archived: false,
    ),
  ],
);

const _archivedCatalog = HabitCatalog(
  categories: [],
  habits: [
    HabitListEntry(
      id: 'habit-1',
      name: 'Morning walk',
      measurementType: MeasurementType.duration,
      scheduleSummary: 'Daily',
      currentStreak: 0,
      archived: true,
    ),
  ],
);
