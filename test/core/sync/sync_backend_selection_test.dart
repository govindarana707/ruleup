import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/core/config/app_config.dart';

void main() {
  test('habit sync backend selection supports staged modes', () {
    expect(
      AppConfig.parseHabitSyncBackend('cloudflare'),
      HabitSyncBackend.cloudflare,
    );
    expect(
      AppConfig.parseHabitSyncBackend('supabase'),
      HabitSyncBackend.supabase,
    );
    expect(
      () => AppConfig.parseHabitSyncBackend('dual-write'),
      throwsStateError,
    );
  });
}
