import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;

  setUpAll(() {
    migration = File(
      'supabase/migrations/20260911000800_phase5_rewards_redemption.sql',
    ).readAsStringSync();
  });

  test('redemption binds an owned reward to one stable ledger source', () {
    expect(migration, contains('reward_id uuid'));
    expect(migration, contains('point_ledger_reward_owner_fk'));
    expect(migration, contains("source_type = 'reward_redemption'"));
    expect(migration, contains('source_id = p_redemption_id::text'));
  });

  test('authoritative pricing and spending are serialized in PostgreSQL', () {
    expect(
      migration,
      contains('pg_advisory_xact_lock(hashtextextended(owner_id::text, 0))'),
    );
    expect(migration, contains('selected_reward.points_cost'));
    expect(migration, contains('select coalesce(sum(points), 0)'));
    expect(migration, contains("raise exception 'insufficient points'"));
    expect(migration, isNot(contains('p_points_cost')));
  });

  test('reward image references use stable owner/reward/object paths', () {
    expect(
      migration,
      contains("split_part(image_key, '/', 1) = user_id::text"),
    );
    expect(migration, contains("split_part(image_key, '/', 2) = id::text"));
    expect(migration, contains("\\.(jpg|webp)"));
  });

  test('RPC remains owner-bound with minimum execution grants', () {
    expect(migration, contains('owner_id uuid := auth.uid()'));
    expect(migration, contains('user_id = owner_id'));
    expect(migration, contains('from public, anon'));
    expect(migration, contains('to authenticated'));
  });
}
