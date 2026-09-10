import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/habits/domain/measurement_type.dart';
import 'package:ruleup/features/habits/presentation/habit_list_screen.dart';
import 'package:ruleup/features/habits/presentation/habit_management_provider.dart';

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
