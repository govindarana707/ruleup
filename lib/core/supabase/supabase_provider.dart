import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/config/app_config.dart';
import 'package:ruleup/core/supabase/supabase_database_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Null until SUPABASE_URL and SUPABASE_ANON_KEY are supplied with
/// --dart-define. Keeping this optional ensures Phase 1 cannot alter the live
/// Cloudflare/D1 path merely by adding the Supabase dependency.
final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  if (!AppConfig.hasSupabaseConfiguration) return null;
  final configuration = AppConfig.requireSupabaseConfiguration();
  return SupabaseClient(configuration.url.toString(), configuration.anonKey);
});

final supabaseDatabaseServiceProvider = Provider<SupabaseDatabaseService?>((
  ref,
) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseDatabaseService(client);
});
