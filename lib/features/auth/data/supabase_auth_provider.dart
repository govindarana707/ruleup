import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/supabase/supabase_provider.dart';
import 'package:ruleup/features/auth/data/supabase_auth_data_source.dart';
import 'package:ruleup/features/auth/data/supabase_session_storage.dart';

final supabaseSessionStorageProvider = Provider<SupabaseSessionStorage>(
  (ref) => SecureSupabaseSessionStorage(),
);

final supabaseAuthDataSourceImplProvider =
    Provider<SupabaseAuthDataSourceImpl?>((ref) {
      final client = ref.watch(supabaseClientProvider);
      if (client == null) return null;
      return SupabaseAuthDataSourceImpl(
        client,
        ref.watch(supabaseSessionStorageProvider),
      );
    });

final supabaseAuthDataSourceProvider = Provider<SupabaseAuthDataSource?>(
  (ref) => ref.watch(supabaseAuthDataSourceImplProvider),
);

final supabaseProductionAuthDataSourceProvider =
    Provider<SupabaseProductionAuthDataSource?>(
      (ref) => ref.watch(supabaseAuthDataSourceImplProvider),
    );
