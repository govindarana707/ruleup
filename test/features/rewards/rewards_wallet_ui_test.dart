import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/core/presentation/point_currency_theme.dart';
import 'package:ruleup/core/sync/sync_provider.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/home/presentation/home_dashboard_provider.dart';
import 'package:ruleup/features/rewards/presentation/rewards_wallet_provider.dart';
import 'package:ruleup/features/rewards/presentation/rewards_wallet_screen.dart';

void main() {
  testWidgets('wallet totals and affordability are displayed', (tester) async {
    await _pumpScreen(tester, data: _wallet);

    expect(find.byKey(const Key('reward-wallet-outer-card')), findsOneWidget);
    expect(find.byKey(const Key('available-points-card')), findsOneWidget);
    expect(find.byKey(const Key('lifetime-earned-card')), findsOneWidget);
    expect(find.byKey(const Key('spent-points-card')), findsOneWidget);
    expect(find.text('Available points'), findsOneWidget);
    expect(find.text('80'), findsOneWidget);
    expect(find.text('Lifetime earned'), findsOneWidget);
    expect(find.text('140'), findsOneWidget);
    expect(find.text('Spent points'), findsOneWidget);
    expect(find.text('60'), findsOneWidget);
    expect(find.text('Movie night'), findsOneWidget);
    expect(find.text('50 points'), findsOneWidget);
    expect(find.text('Monetary cap 20'), findsOneWidget);
    expect(find.text('Ready to redeem'), findsOneWidget);
    expect(find.text('Active (2)'), findsOneWidget);
    expect(find.text('Archived (0)'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('reward-wallet-outer-card')),
        matching: find.byKey(const Key('flat-point-coins-icon')),
      ),
      findsNWidgets(3),
    );
    expect(find.byKey(const Key('reward-image-fallback')), findsWidgets);
    expect(
      tester.getSize(find.byKey(const Key('reward-image-movie'))),
      const Size.square(64),
    );

    await _reveal(tester, find.text('40 points to go'));
    expect(find.text('40 points to go'), findsOneWidget);
    await _reveal(
      tester,
      find.byKey(const Key('redeem-reward-movie')),
      reverse: true,
    );
    final redeemStyle = tester
        .widget<FilledButton>(find.byKey(const Key('redeem-reward-movie')))
        .style!;
    expect(
      redeemStyle.backgroundColor!.resolve(<WidgetState>{}),
      PointCurrencyTheme.gold,
    );
    expect(find.text('Redeem reward'), findsOneWidget);
    await _reveal(tester, find.byKey(const Key('redeem-reward-expensive')));
    expect(find.text('Not enough points'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('redeem-reward-expensive')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('create and edit flows validate and save reward drafts', (
    tester,
  ) async {
    final saved = <RewardDraft>[];
    await _pumpScreen(
      tester,
      data: _wallet,
      save: (userId, draft) async {
        saved.add(draft);
        return draft.id ?? 'new-reward';
      },
    );

    await _reveal(tester, find.byKey(const Key('create-reward-button')));
    await tester.tap(find.byKey(const Key('create-reward-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-reward-button')));
    await tester.pump();
    expect(find.text('Enter a reward name.'), findsOneWidget);
    expect(find.text('Enter a positive whole number.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('reward-name-field')),
      'New headphones',
    );
    await tester.enterText(find.byKey(const Key('reward-cost-field')), '200');
    await tester.enterText(find.byKey(const Key('reward-cap-field')), '75.5');
    await tester.tap(find.byKey(const Key('save-reward-button')));
    await tester.pumpAndSettle();
    expect(saved.last.name, 'New headphones');
    expect(saved.last.pointsCost, '200');
    expect(saved.last.monetaryCap, '75.5');

    await _reveal(
      tester,
      find.byKey(const Key('reward-card-movie')),
      reverse: true,
    );
    await tester.tap(find.byKey(const Key('reward-card-movie')));
    await tester.pumpAndSettle();
    expect(find.text('Edit reward'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('reward-name-field')),
      'Cinema night',
    );
    await tester.tap(find.byKey(const Key('save-reward-button')));
    await tester.pumpAndSettle();
    expect(saved.last.id, 'movie');
    expect(saved.last.name, 'Cinema night');
  });

  testWidgets('archive confirmation and restore call scoped actions', (
    tester,
  ) async {
    String? archived;
    String? restored;
    await _pumpScreen(
      tester,
      data: _wallet,
      archive: (userId, rewardId) async => archived = '$userId/$rewardId',
    );

    await tester.tap(find.byTooltip('Reward actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('Archive reward?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-archive-reward-button')));
    await tester.pumpAndSettle();
    expect(archived, 'user-1/movie');

    await _pumpScreen(
      tester,
      data: _archivedWallet,
      restore: (userId, rewardId) async => restored = '$userId/$rewardId',
    );
    await tester.tap(find.text('Archived (1)'));
    await tester.pump();
    await tester.tap(find.byTooltip('Reward actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(restored, 'user-1/archived');
  });

  testWidgets('redemption requires confirmation and refreshes wallet totals', (
    tester,
  ) async {
    var current = _wallet;
    var redemptions = 0;
    await _pumpScreen(
      tester,
      dataLoader: () async => current,
      redeem: (userId, rewardId) async {
        redemptions++;
        current = RewardsWalletData(
          availablePoints: 30,
          lifetimeEarned: 140,
          spentPoints: 110,
          rewards: _wallet.rewards,
        );
      },
    );

    await _reveal(tester, find.byKey(const Key('redeem-reward-movie')));
    await tester.tap(find.byKey(const Key('redeem-reward-movie')));
    await tester.pumpAndSettle();
    expect(find.text('Redeem reward?'), findsOneWidget);
    expect(find.textContaining('30 points remaining'), findsOneWidget);
    final confirmationStyle = tester
        .widget<FilledButton>(find.byKey(const Key('confirm-redeem-button')))
        .style!;
    expect(
      confirmationStyle.backgroundColor!.resolve(<WidgetState>{}),
      PointCurrencyTheme.gold,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(redemptions, 0);

    await _reveal(
      tester,
      find.byKey(const Key('redeem-reward-movie')),
      reverse: true,
    );
    await tester.tap(find.byKey(const Key('redeem-reward-movie')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-redeem-button')));
    await tester.pumpAndSettle();
    expect(redemptions, 1);
    expect(find.text('30'), findsOneWidget);
    expect(find.text('110'), findsOneWidget);
    expect(find.text('Movie night redeemed for 50 points'), findsOneWidget);
  });

  testWidgets('insufficient balance blocks redemption before confirmation', (
    tester,
  ) async {
    var called = false;
    await _pumpScreen(
      tester,
      data: const RewardsWalletData(
        availablePoints: 5,
        lifetimeEarned: 5,
        spentPoints: 0,
        rewards: [
          RewardListItem(
            id: 'too-expensive',
            name: 'Day trip',
            pointsCost: 25,
            sortOrder: 0,
            archived: false,
          ),
        ],
      ),
      redeem: (userId, rewardId) async => called = true,
    );

    await _reveal(tester, find.text('20 points to go'));
    expect(find.text('20 points to go'), findsOneWidget);
    await tester.tap(find.byKey(const Key('redeem-reward-too-expensive')));
    await tester.pump();
    expect(find.text('Redeem reward?'), findsNothing);
    expect(called, isFalse);
  });

  testWidgets('renders loading, error, empty, offline, and syncing states', (
    tester,
  ) async {
    final pending = Completer<RewardsWalletData>();
    await _pumpScreen(tester, future: pending.future, settle: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await _pumpScreen(tester, error: Exception('database unavailable'));
    expect(find.text("Couldn't load rewards"), findsOneWidget);

    await _pumpScreen(tester, data: _emptyWallet);
    expect(find.text('Create a reward worth working toward'), findsOneWidget);

    await _pumpScreen(tester, data: _emptyWallet, offline: true);
    expect(find.textContaining('Offline'), findsOneWidget);

    await _pumpScreen(tester, data: _emptyWallet, syncing: true);
    expect(find.text('Syncing rewards and wallet…'), findsOneWidget);
  });

  testWidgets('wallet remains usable on a narrow screen with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pumpScreen(tester, data: _wallet);

    expect(find.text('Available points'), findsOneWidget);
    expect(find.text('Lifetime earned'), findsOneWidget);
    await _reveal(tester, find.byKey(const Key('redeem-reward-movie')));
    expect(find.byKey(const Key('redeem-reward-movie')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wallet explanation defines each authoritative total', (
    tester,
  ) async {
    await _pumpScreen(tester, data: _wallet);

    await tester.tap(find.byKey(const Key('wallet-how-it-works')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('wallet-explanation')), findsOneWidget);
    expect(
      find.text('Points you can spend on rewards right now.'),
      findsOneWidget,
    );
    expect(
      find.text('Every point you have earned from your habits.'),
      findsOneWidget,
    );
    expect(find.text('Points already used to redeem rewards.'), findsOneWidget);
  });
}

Future<void> _reveal(
  WidgetTester tester,
  Finder finder, {
  bool reverse = false,
}) async {
  await tester.dragUntilVisible(
    finder,
    find.byKey(const Key('rewards-wallet-scroll')),
    Offset(0, reverse ? 300 : -300),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  RewardsWalletData? data,
  Future<RewardsWalletData>? future,
  Future<RewardsWalletData> Function()? dataLoader,
  Object? error,
  RewardSaveAction? save,
  RewardMutationAction? archive,
  RewardMutationAction? restore,
  RewardMutationAction? redeem,
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
        rewardsWalletProvider.overrideWith((ref, _) async {
          if (error != null) throw error;
          if (dataLoader != null) return dataLoader();
          if (future != null) return future;
          return data!;
        }),
        rewardSaveActionProvider.overrideWithValue(
          save ?? (userId, draft) async => draft.id ?? 'new-reward',
        ),
        rewardArchiveActionProvider.overrideWithValue(
          archive ?? (userId, rewardId) async {},
        ),
        rewardRestoreActionProvider.overrideWithValue(
          restore ?? (userId, rewardId) async {},
        ),
        rewardRedeemActionProvider.overrideWithValue(
          redeem ?? (userId, rewardId) async {},
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
      child: const MaterialApp(home: RewardsWalletScreen(userId: 'user-1')),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

const _wallet = RewardsWalletData(
  availablePoints: 80,
  lifetimeEarned: 140,
  spentPoints: 60,
  rewards: [
    RewardListItem(
      id: 'movie',
      name: 'Movie night',
      pointsCost: 50,
      monetaryCap: 20,
      sortOrder: 0,
      archived: false,
    ),
    RewardListItem(
      id: 'expensive',
      name: 'New book',
      pointsCost: 120,
      sortOrder: 1,
      archived: false,
    ),
  ],
);

const _emptyWallet = RewardsWalletData(
  availablePoints: 0,
  lifetimeEarned: 0,
  spentPoints: 0,
  rewards: [],
);

const _archivedWallet = RewardsWalletData(
  availablePoints: 10,
  lifetimeEarned: 10,
  spentPoints: 0,
  rewards: [
    RewardListItem(
      id: 'archived',
      name: 'Old reward',
      pointsCost: 5,
      sortOrder: 0,
      archived: true,
    ),
  ],
);

class _SyncingController extends SyncController {
  @override
  SyncState build() => const SyncState(status: SyncStatus.syncing);
}
