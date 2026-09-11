import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('import checkpoints are service-role-only and restart aware', () {
    final migration = File(
      'supabase/migrations/20260911001000_phase7_cutover_import.sql',
    ).readAsStringSync();
    expect(migration, contains('legacy_import_runs'));
    expect(migration, contains("status in ('in_progress', 'completed')"));
    expect(migration, contains('force row level security'));
    expect(migration, contains('revoke all'));
    expect(migration, contains('to service_role'));
  });

  test('production username auth preserves UUID-derived identity', () {
    final source = File('supabase/functions/username-auth/index.ts')
        .readAsStringSync();
    expect(source, contains('crypto.randomUUID()'));
    expect(source, contains(r'`${userId}@auth.ruleup.invalid`'));
    expect(source, contains("identity_source: 'ruleup_supabase'"));
    expect(source, isNot(contains('password_hash')));
  });
}
