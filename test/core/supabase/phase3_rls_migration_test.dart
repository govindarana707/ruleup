import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Phase 3 tables retain owner-scoped CRUD policies', () {
    final rls = File(
      'supabase/migrations/20260910000200_row_level_security.sql',
    ).readAsStringSync();
    final hardening = File(
      'supabase/migrations/20260911000500_phase3_habit_sync_hardening.sql',
    ).readAsStringSync();
    for (final table in const [
      'categories',
      'habits',
      'habit_options',
      'habit_schedules',
      'point_rules',
      'habit_pauses',
      'habit_reminders',
    ]) {
      expect(rls, contains("'$table'"));
      expect(
        hardening,
        contains('alter table public.$table force row level security'),
      );
    }
    expect(rls, contains('using (user_id = auth.uid())'));
    expect(rls, contains('with check (user_id = auth.uid())'));
    expect(rls, contains('sync_changes_select_own'));
    expect(rls.toLowerCase(), isNot(contains('using (true)')));
    expect(rls.toLowerCase(), isNot(contains('with check (true)')));
  });

  test('Phase 3 child keys bind parent and owner together', () {
    final schema = File('supabase/migrations/20260910000100_ruleup_schema.sql')
        .readAsStringSync();
    expect(
      RegExp(
        r'foreign key \(habit_id, user_id\)\s+references public\.habits\(id, user_id\)',
        caseSensitive: false,
      ).allMatches(schema).length,
      greaterThanOrEqualTo(5),
    );
    expect(schema, contains('foreign key (category_id, user_id)'));
  });
}
