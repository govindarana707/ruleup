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
