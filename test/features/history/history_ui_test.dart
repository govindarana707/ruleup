import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/check_ins/presentation/daily_check_in_provider.dart';
import 'package:ruleup/features/history/presentation/history_provider.dart';
import 'package:ruleup/features/history/presentation/history_screen.dart';

void main() {
  testWidgets('calendar renders history states and streak summaries', (
    tester,
  ) async {
    await _pumpScreen(tester, data: _history);

    expect(find.byKey(const Key('history-calendar')), findsOneWidget);
    expect(find.text('Current streak'), findsOneWidget);
    expect(find.text('4 days'), findsOneWidget);
    expect(find.text('Longest streak'), findsOneWidget);
    expect(find.text('12 days'), findsOneWidget);
    expect(find.text('January 5, 2026'), findsOneWidget);

    await _scrollToEntries(tester);
    expect(find.text('Completed'), findsWidgets);
    expect(find.text('Missed'), findsWidgets);
    expect(find.text('Paused'), findsWidgets);
    expect(find.text('Not scheduled'), findsWidgets);
    expect(find.text('Deep session'), findsOneWidget);
    expect(find.text('+10 points'), findsOneWidget);
    expect(find.text('-3 points'), findsOneWidget);
  });

  testWidgets('habit and completion filters narrow visible history', (
    tester,
  ) async {
    await _pumpScreen(tester, data: _history);
    await _scrollToEntries(tester);

    await tester.tap(find.byKey(const Key('history-habit-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meditate').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history-entry-meditate')), findsOneWidget);
    expect(find.byKey(const Key('history-entry-study')), findsNothing);

    await tester.tap(find.text('Missed'));
    await tester.pumpAndSettle();
    expect(find.text('No matching history'), findsOneWidget);
  });

  testWidgets('entry opens read-only check-in details', (tester) async {
    await _pumpScreen(tester, data: _history);
    await _scrollToEntries(tester);
    await tester.tap(find.byKey(const Key('history-entry-study')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('history-detail-sheet')), findsOneWidget);
    expect(find.text('Selected option'), findsOneWidget);
    expect(find.text('Deep session'), findsWidgets);
    expect(find.text('Measured value'), findsOneWidget);
    expect(find.text('60'), findsOneWidget);
    expect(find.text('Note'), findsOneWidget);
    expect(find.text('Focused well'), findsOneWidget);
    expect(find.text('+10 points'), findsWidgets);
  });

  testWidgets('history list and detail expose an editable check-in', (
    tester,
  ) async {
    CheckInSubmission? submitted;
    await _pumpScreen(
      tester,
      data: _editableHistory,
      submit: (_, value) async {
        submitted = value;
        return const CheckInSubmitResult(points: 3, updated: true);
      },
    );
    await _scrollToEntries(tester);

    await tester.tap(find.byKey(const Key('edit-history-check-in-study')));
    await tester.pumpAndSettle();
    expect(find.text('Edit check-in'), findsOneWidget);
    await tester.tap(find.text('No'));
    await tester.tap(find.byKey(const Key('submit-check-in-button')));
    await tester.pumpAndSettle();
    expect(submitted?.checkInId, 'history-check-in');
    expect(submitted?.completed, isFalse);
  });

  testWidgets('history detail opens the same editable check-in', (
    tester,
  ) async {
    CheckInSubmission? submitted;
    await _pumpScreen(
      tester,
      data: _editableHistory,
      submit: (_, value) async {
        submitted = value;
        return const CheckInSubmitResult(points: 3, updated: true);
      },
    );
    await _scrollToEntries(tester);

    await tester.tap(find.byKey(const Key('history-entry-study')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-history-detail-study')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No'));
    await tester.tap(find.byKey(const Key('submit-check-in-button')));
    await tester.pumpAndSettle();

    expect(submitted?.checkInId, 'history-check-in');
    expect(submitted?.completed, isFalse);
  });

  testWidgets('renders loading, empty, error, offline, and syncing states', (
    tester,
  ) async {
    final pending = Completer<HistoryDayData>();
    await _pumpScreen(tester, future: pending.future, settle: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await _pumpScreen(tester, error: Exception('database unavailable'));
    expect(find.text("Couldn't load history"), findsOneWidget);

    await _pumpScreen(tester, data: _emptyHistory);
    await _scrollToEntries(tester);
    expect(find.text('No habit history for this date'), findsOneWidget);

    await _pumpScreen(tester, data: _emptyHistory, offline: true);
    expect(find.textContaining('Offline'), findsOneWidget);

    await _pumpScreen(tester, data: _emptyHistory, syncing: true);
    expect(find.text('Syncing your history…'), findsOneWidget);
  });
}

Future<void> _scrollToEntries(WidgetTester tester) async {
  await tester.drag(
    find.byKey(const Key('history-scroll')),
    const Offset(0, -620),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  HistoryDayData? data,
  Future<HistoryDayData>? future,
  Object? error,
  bool offline = false,
  bool syncing = false,
  CheckInSubmitAction? submit,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        historyNowProvider.overrideWithValue(DateTime(2026, 1, 5, 10)),
        backendHealthProvider.overrideWith((ref) async {
          if (offline) throw Exception('offline');
        }),
        if (syncing)
          syncControllerProvider.overrideWith(_SyncingController.new),
        historyDayProvider.overrideWith((ref, query) async {
          if (error != null) throw error;
          if (future != null) return future;
          return data!;
        }),
        if (submit != null)
          checkInSubmitActionProvider.overrideWithValue(submit),
      ],
      child: const MaterialApp(home: HistoryScreen(userId: 'user-1')),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

final _history = HistoryDayData(
  date: DateTime(2026, 1, 5),
  currentStreak: 4,
  longestStreak: 12,
  habits: const [
    HistoryHabitFilter(id: 'study', name: 'Study'),
    HistoryHabitFilter(id: 'meditate', name: 'Meditate'),
    HistoryHabitFilter(id: 'walk', name: 'Walk'),
    HistoryHabitFilter(id: 'journal', name: 'Journal'),
  ],
  entries: [
    HistoryEntry(
      habitId: 'study',
      habitName: 'Study',
      categoryName: 'Learning',
      scheduleSummary: 'Daily',
      status: HistoryEntryStatus.completed,
      selectedOption: 'Deep session',
      measuredValue: 60,
      points: 10,
      note: 'Focused well',
      checkedInAt: DateTime(2026, 1, 5, 18),
    ),
    const HistoryEntry(
      habitId: 'walk',
      habitName: 'Walk',
      scheduleSummary: 'Daily',
      status: HistoryEntryStatus.missed,
      points: -3,
    ),
    const HistoryEntry(
      habitId: 'meditate',
      habitName: 'Meditate',
      scheduleSummary: 'Daily',
      status: HistoryEntryStatus.paused,
      points: 0,
    ),
    const HistoryEntry(
      habitId: 'journal',
      habitName: 'Journal',
      scheduleSummary: 'Tue, Thu',
      status: HistoryEntryStatus.nonScheduled,
      points: 0,
    ),
  ],
);

final _emptyHistory = HistoryDayData(
  date: DateTime(2026, 1, 5),
  currentStreak: 0,
  longestStreak: 0,
  habits: const [],
  entries: const [],
);

final _editableHistory = HistoryDayData(
  date: DateTime(2026, 1, 5),
  currentStreak: 1,
  longestStreak: 1,
  habits: const [HistoryHabitFilter(id: 'study', name: 'Study')],
  entries: [
    HistoryEntry(
      habitId: 'study',
      habitName: 'Study',
      scheduleSummary: 'Daily',
      status: HistoryEntryStatus.completed,
      points: 3,
      checkInId: 'history-check-in',
      editableUntil: DateTime(2026, 1, 6, 12),
      completed: true,
    ),
  ],
);

class _SyncingController extends SyncController {
  @override
  SyncState build() => const SyncState(status: SyncStatus.syncing);
}
