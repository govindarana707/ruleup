import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;
  late String cleanupFunction;

  setUpAll(() {
    migration = File(
      'supabase/migrations/20260911000900_phase6_reminders_sync_cleanup.sql',
    ).readAsStringSync();
    cleanupFunction = File('supabase/functions/cleanup-reward-images/index.ts')
        .readAsStringSync();
  });

  test('reminders retain owner RLS and minute-precision cloud metadata', () {
    expect(migration, contains('habit_reminders force row level security'));
    expect(migration, contains('habit_reminders_minute_precision'));
    expect(migration, contains("date_part('second', time_of_day) = 0"));
  });

  test('change feed remains trigger-written and owner-readable only', () {
    expect(migration, contains('sync_changes force row level security'));
    expect(
      migration,
      contains(
        'revoke insert, update, delete, truncate on public.sync_changes',
      ),
    );
    expect(migration, contains('grant select on public.sync_changes'));
  });

  test('account cleanup derives owner and deletes through Storage API', () {
    expect(cleanupFunction, contains('supabase.auth.getUser(token)'));
    expect(cleanupFunction, contains('const ownerId = userData.user.id'));
    expect(cleanupFunction, contains('.remove('));
    expect(cleanupFunction, isNot(contains('service_role')));
    expect(cleanupFunction, isNot(contains('SUPABASE_SERVICE_ROLE_KEY')));
    expect(cleanupFunction, isNot(contains('request.json')));
  });

  test('Storage updates retain the complete owner path shape', () {
    expect(migration, contains('reward_images_update_own'));
    expect(
      migration,
      contains("(storage.foldername(name))[1] = auth.uid()::text"),
    );
    expect(migration, contains(r'\.(jpg|webp)$'));
  });
}
