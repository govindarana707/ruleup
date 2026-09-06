import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/check_ins/presentation/daily_check_in_provider.dart';
import 'package:ruleup/features/check_ins/presentation/daily_check_in_screen.dart';
import 'package:ruleup/features/habits/domain/measurement_type.dart';
import 'package:ruleup/features/home/presentation/home_dashboard_provider.dart';

void main() {
  testWidgets('yes/no habit supports one-tap submit and point feedback', (
    tester,
  ) async {
    CheckInSubmission? submitted;
    await _pumpScreen(
      tester,
      data: _data([_yesNoHabit]),
      submit: (userId, submission) async {
        submitted = submission;
        return const CheckInSubmitResult(points: 5, updated: false);
      },
    );

    expect(find.text('Read today'), findsOneWidget);
    expect(find.text('Learning'), findsOneWidget);
    expect(find.text('3 day streak'), findsOneWidget);
    await tester.tap(find.byKey(const Key('check-in-action-yes-no')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(submitted?.habitId, 'yes-no');
    expect(submitted?.measuredValue, isNull);
    expect(find.text('+5 points earned'), findsOneWidget);
  });

  testWidgets('configured option and note are submitted together', (
    tester,
  ) async {
    CheckInSubmission? submitted;
    await _pumpScreen(
      tester,
      data: _data([_optionHabit]),
      submit: (userId, submission) async {
        submitted = submission;
        return const CheckInSubmitResult(points: 10, updated: false);
      },
    );

    await tester.tap(find.byKey(const Key('check-in-action-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('check-in-option-option-2')));
    await tester.enterText(
      find.byKey(const Key('check-in-note-field')),
      'Strong session',
    );
    await tester.tap(find.byKey(const Key('submit-check-in-button')));
    await tester.pumpAndSettle();

    expect(submitted?.optionId, 'option-2');
    expect(submitted?.measuredValue, isNull);
    expect(submitted?.note, 'Strong session');
    expect(find.text('+10 points earned'), findsOneWidget);
  });

  testWidgets('numeric habits validate and submit custom values', (
    tester,
  ) async {
    CheckInSubmission? submitted;
    await _pumpScreen(
      tester,
      data: _data([_numericHabit]),
      submit: (userId, submission) async {
        submitted = submission;
        return const CheckInSubmitResult(points: -2, updated: false);
      },
    );

    await tester.tap(find.byKey(const Key('check-in-action-numeric')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('submit-check-in-button')));
    await tester.pump();
    expect(find.text('Enter a valid value.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('check-in-value-field')),
      '12.5',
    );
    await tester.tap(find.byKey(const Key('submit-check-in-button')));
    await tester.pumpAndSettle();

    expect(submitted?.measuredValue, 12.5);
    expect(find.text('2 points deducted'), findsOneWidget);
  });

  testWidgets('existing check-in can be edited within its window', (
    tester,
  ) async {
    CheckInSubmission? submitted;
    await _pumpScreen(
      tester,
      data: _data([_editableHabit]),
      submit: (userId, submission) async {
        submitted = submission;
        return const CheckInSubmitResult(points: 8, updated: true);
      },
    );

    await tester.tap(find.text('All'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('edit-check-in-editable')));
    await tester.pumpAndSettle();
    expect(find.text('Edit check-in'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('check-in-note-field')))
          .controller
          ?.text,
      'Original note',
    );
    await tester.enterText(find.byKey(const Key('check-in-value-field')), '45');
    await tester.enterText(
      find.byKey(const Key('check-in-note-field')),
      'Updated note',
    );
    await tester.tap(find.byKey(const Key('submit-check-in-button')));
    await tester.pumpAndSettle();

    expect(submitted?.checkInId, 'check-in-1');
    expect(submitted?.measuredValue, 45);
    expect(submitted?.note, 'Updated note');
    expect(find.text('Check-in updated · +8 points total'), findsOneWidget);
  });

  testWidgets('locked check-in is clearly displayed and cannot edit', (
    tester,
  ) async {
    await _pumpScreen(tester, data: _data([_lockedHabit]));
    await tester.tap(find.text('All'));
    await tester.pump();

    expect(find.text('Locked'), findsOneWidget);
    expect(find.byKey(const Key('edit-check-in-locked')), findsNothing);
    await tester.tap(find.byKey(const Key('check-in-card-locked')));
    await tester.pump();
    expect(find.byKey(const Key('check-in-form-sheet')), findsNothing);
  });

  testWidgets('renders empty, error, loading, and offline states', (
    tester,
  ) async {
    await _pumpScreen(tester, data: _data(const []));
    expect(find.text('Nothing scheduled today'), findsOneWidget);

    await _pumpScreen(tester, error: Exception('database unavailable'));
    expect(find.text("Couldn't load today’s habits"), findsOneWidget);

    final pending = Completer<DailyCheckInData>();
    await _pumpScreen(tester, future: pending.future, settle: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await _pumpScreen(tester, data: _data(const []), offline: true);
    expect(find.textContaining('Offline'), findsOneWidget);

    await _pumpScreen(tester, data: _data(const []), syncing: true);
    expect(find.text('Syncing today’s progress…'), findsOneWidget);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  DailyCheckInData? data,
  Future<DailyCheckInData>? future,
  Object? error,
  CheckInSubmitAction? submit,
  bool offline = false,
  bool syncing = false,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        backendHealthProvider.overrideWith((ref) async {
          if (offline) throw Exception('offline');
        }),
        if (syncing)
          syncControllerProvider.overrideWith(_SyncingController.new),
        dailyCheckInProvider.overrideWith((ref, _) async {
          if (error != null) throw error;
          if (future != null) return future;
          return data!;
        }),
        checkInSubmitActionProvider.overrideWithValue(
          submit ??
              (userId, submission) async =>
                  const CheckInSubmitResult(points: 0, updated: false),
        ),
        homeDashboardProvider.overrideWith(
          (ref, _) async => const HomeDashboardData(
            availablePoints: 0,
            currentStreak: 0,
            completedToday: 0,
            applicableToday: 0,
            activeHabitCount: 0,
          ),
        ),
      ],
      child: const MaterialApp(home: DailyCheckInScreen(userId: 'user-1')),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

DailyCheckInData _data(List<DailyHabitEntry> habits) =>
    DailyCheckInData(date: DateTime(2026, 1, 5), habits: habits);

const _yesNoHabit = DailyHabitEntry(
  id: 'yes-no',
  name: 'Read today',
  categoryName: 'Learning',
  measurementType: MeasurementType.yesNo,
  scheduleSummary: 'Daily',
  reminderTime: '20:00',
  currentStreak: 3,
);

const _optionHabit = DailyHabitEntry(
  id: 'options',
  name: 'Study',
  measurementType: MeasurementType.duration,
  scheduleSummary: 'Mon, Wed, Fri',
  currentStreak: 2,
  options: [
    CheckInOption(id: 'option-1', label: 'Short', numericValue: 15),
    CheckInOption(id: 'option-2', label: 'Deep', numericValue: 60),
  ],
);

const _numericHabit = DailyHabitEntry(
  id: 'numeric',
  name: 'Screen time',
  measurementType: MeasurementType.value,
  scheduleSummary: 'Daily',
  currentStreak: 0,
);

final _editableHabit = DailyHabitEntry(
  id: 'editable',
  name: 'Meditate',
  measurementType: MeasurementType.duration,
  scheduleSummary: 'Daily',
  currentStreak: 4,
  checkIn: ExistingCheckIn(
    id: 'check-in-1',
    measuredValue: 30,
    note: 'Original note',
    awardedPoints: 5,
    editableUntil: DateTime(2026, 1, 6, 12),
    locked: false,
  ),
);

final _lockedHabit = DailyHabitEntry(
  id: 'locked',
  name: 'Walk',
  measurementType: MeasurementType.count,
  scheduleSummary: 'Daily',
  currentStreak: 8,
  checkIn: ExistingCheckIn(
    id: 'check-in-2',
    measuredValue: 5000,
    awardedPoints: 10,
    editableUntil: DateTime(2026, 1, 5, 1),
    locked: true,
  ),
);

class _SyncingController extends SyncController {
  @override
  SyncState build() => const SyncState(status: SyncStatus.syncing);
}
