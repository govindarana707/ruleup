import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin boundary around Supabase so future remote repositories do not need to
/// construct or globally initialize their own clients.
class SupabaseDatabaseService {
  const SupabaseDatabaseService(this.client);

  final SupabaseClient client;

  SupabaseQueryBuilder from(String table) => client.from(table);

  PostgrestFilterBuilder<dynamic> rpc(
    String function, {
    Map<String, dynamic>? params,
  }) => client.rpc(function, params: params);
}
