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

  static Uri get apiBaseUrl => _createApiBaseUrl();
  static bool get showDevelopmentConnectionErrors => !kReleaseMode;

  /// Supabase is required for production-default builds. Local development
  /// and explicit rollback builds can continue to use the legacy Worker.
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static bool get hasSupabaseConfiguration =>
      supabaseUrl.isNotEmpty || supabaseAnonKey.isNotEmpty;
  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static const _backendOverride = String.fromEnvironment('RULEUP_BACKEND');
  static const _legacyBackendOverride = String.fromEnvironment(
    'RULEUP_HABIT_SYNC_BACKEND',
  );

  static RuleUpBackend get activeBackend => resolveBackend(
    backendOverride: _backendOverride,
    legacyOverride: _legacyBackendOverride,
    releaseMode: kReleaseMode,
  );

  static HabitSyncBackend get habitSyncBackend =>
      activeBackend == RuleUpBackend.supabase
      ? HabitSyncBackend.supabase
      : HabitSyncBackend.cloudflare;

  static String get activeBackendLabel => switch (activeBackend) {
    RuleUpBackend.local => 'Local development (Cloudflare/D1)',
    RuleUpBackend.supabase => 'Supabase production',
    RuleUpBackend.legacy => 'Legacy Cloudflare/D1',
  };

  static RuleUpBackend resolveBackend({
    required String backendOverride,
    required String legacyOverride,
    required bool releaseMode,
  }) {
    if (backendOverride.isNotEmpty) {
      return parseBackend(backendOverride);
    }
    if (legacyOverride.isNotEmpty) {
      return parseHabitSyncBackend(legacyOverride) == HabitSyncBackend.supabase
          ? RuleUpBackend.supabase
          : RuleUpBackend.legacy;
    }
    return releaseMode ? RuleUpBackend.supabase : RuleUpBackend.local;
  }

  static RuleUpBackend parseBackend(String value) => switch (value) {
    'local' => RuleUpBackend.local,
    'supabase' => RuleUpBackend.supabase,
    'legacy' || 'cloudflare' => RuleUpBackend.legacy,
    _ => throw StateError('RULEUP_BACKEND must be local, supabase, or legacy.'),
  };

  static HabitSyncBackend parseHabitSyncBackend(String value) =>
      switch (value) {
        'cloudflare' => HabitSyncBackend.cloudflare,
        'legacy' => HabitSyncBackend.cloudflare,
        'supabase' => HabitSyncBackend.supabase,
        _ => throw StateError(
          'RULEUP_HABIT_SYNC_BACKEND must be cloudflare, legacy, or supabase.',
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

  static void validateStartupConfiguration() {
    if (activeBackend == RuleUpBackend.supabase) {
      requireSupabaseConfiguration();
    } else {
      _createApiBaseUrl();
    }
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
    if (activeBackend == RuleUpBackend.supabase) {
      throw StateError(
        'The legacy API URL is unavailable in Supabase production mode.',
      );
    }
    if (kReleaseMode) {
      throw StateError('RULEUP_API_BASE_URL is required for release builds.');
    }
    return Uri(scheme: 'http', host: developmentHost, port: developmentPort);
  }
}

enum HabitSyncBackend { cloudflare, supabase }

enum RuleUpBackend { local, supabase, legacy }
