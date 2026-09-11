import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;

  setUpAll(() {
    migration = File(
      'supabase/migrations/20260911000700_phase4_financial_sync.sql',
    ).readAsStringSync();
  });

  test('financial tables are read-only and mutations use owner-bound RPCs', () {
    expect(
      migration,
      contains(
        'revoke insert, update, delete on public.check_ins, public.point_ledger',
      ),
    );
    expect(migration, contains('owner_id uuid := auth.uid()'));
    expect(migration, contains('submitted points do not match the owned rule'));
    expect(migration, contains("from public, anon"));
  });

  test('check-in retries preserve one stable logical ledger effect', () {
    expect(migration, contains('pg_advisory_xact_lock'));
    expect(migration, contains('client_updated_at'));
    expect(
      migration,
      contains('on conflict (user_id, source_type, source_id) do update'),
    );
    expect(
      migration,
      contains('public.point_ledger.points is distinct from excluded.points'),
    );
  });

  test('missed penalties serialize on stable occurrence identity', () {
    expect(migration, contains("source_type = 'missed_check_in'"));
    expect(migration, contains("owner_id::text || ':' || source_key"));
    expect(migration, contains('penalty must be non-positive'));
  });

  test('wallet remains a derived Phase 1 ledger aggregation', () {
    final schema = File('supabase/migrations/20260910000100_ruleup_schema.sql')
        .readAsStringSync();
    expect(schema, contains('create view public.wallet_totals'));
    expect(schema, contains('coalesce(sum(points), 0)'));
    expect(schema, contains('where points > 0'));
    expect(
      schema,
      contains("points < 0 and source_type = 'reward_redemption'"),
    );
    expect(migration, isNot(contains('create table public.wallet')));
  });
}
