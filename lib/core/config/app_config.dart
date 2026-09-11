import 'package:flutter/foundation.dart';

abstract final class AppConfig {
  static const _baseUrlOverride = String.fromEnvironment('RULEUP_API_BASE_URL');
  static const developmentHost = String.fromEnvironment(
    'RULEUP_API_HOST',
    defaultValue: '10.0.2.2',
  );
  static const developmentPort = int.fromEnvironment(
    'RULEUP_API_PORT',
    defaultValue: 8787,
  );

  static final apiBaseUrl = _createApiBaseUrl();
  static bool get showDevelopmentConnectionErrors => !kReleaseMode;

  /// Supabase is optional during the phased migration. Existing Cloudflare
  /// code must not read these values until the Supabase data source is enabled.
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static bool get hasSupabaseConfiguration =>
      supabaseUrl.isNotEmpty || supabaseAnonKey.isNotEmpty;
  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static const _habitSyncBackend = String.fromEnvironment(
    'RULEUP_HABIT_SYNC_BACKEND',
    defaultValue: 'cloudflare',
  );

  static HabitSyncBackend get habitSyncBackend =>
      parseHabitSyncBackend(_habitSyncBackend);

  static HabitSyncBackend parseHabitSyncBackend(String value) =>
      switch (value) {
        'cloudflare' => HabitSyncBackend.cloudflare,
        'supabase' => HabitSyncBackend.supabase,
        _ => throw StateError(
          'RULEUP_HABIT_SYNC_BACKEND must be cloudflare or supabase.',
        ),
      };

  static ({Uri url, String anonKey}) requireSupabaseConfiguration() {
    if (!isSupabaseConfigured) {
      throw StateError(
        'SUPABASE_URL and SUPABASE_ANON_KEY must be supplied together.',
      );
    }
    final url = Uri.parse(supabaseUrl);
    if (!url.hasScheme || !url.hasAuthority) {
      throw StateError('SUPABASE_URL must be an absolute URL.');
    }
    if (kReleaseMode && url.scheme != 'https') {
      throw StateError('Release builds require an HTTPS SUPABASE_URL.');
    }
    return (url: url, anonKey: supabaseAnonKey);
  }

  static Uri _createApiBaseUrl() {
    if (_baseUrlOverride.isNotEmpty) {
      final url = Uri.parse(_baseUrlOverride);
      if (!url.hasScheme || !url.hasAuthority) {
        throw StateError('RULEUP_API_BASE_URL must be an absolute URL.');
      }
      if (kReleaseMode && url.scheme != 'https') {
        throw StateError('Release builds require an HTTPS API base URL.');
      }
      return url;
    }
    if (kReleaseMode) {
      throw StateError('RULEUP_API_BASE_URL is required for release builds.');
    }
    return Uri(scheme: 'http', host: developmentHost, port: developmentPort);
  }
}

enum HabitSyncBackend { cloudflare, supabase }
