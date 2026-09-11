import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/core/config/app_config.dart';
import 'package:ruleup/core/supabase/supabase_provider.dart';

void main() {
  test('Supabase client follows the build configuration state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    if (!AppConfig.hasSupabaseConfiguration) {
      expect(container.read(supabaseClientProvider), isNull);
      expect(container.read(supabaseDatabaseServiceProvider), isNull);
    } else if (!AppConfig.isSupabaseConfigured) {
      expect(
        () => container.read(supabaseClientProvider),
        throwsA(isA<StateError>()),
      );
    } else {
      expect(container.read(supabaseClientProvider), isNotNull);
      expect(container.read(supabaseDatabaseServiceProvider), isNotNull);
    }
  });
}
