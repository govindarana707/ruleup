import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SupabaseSessionStorage {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> session);
  Future<void> delete();
}

class SecureSupabaseSessionStorage implements SupabaseSessionStorage {
  SecureSupabaseSessionStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'ruleup_supabase_session';
  final FlutterSecureStorage _storage;

  @override
  Future<Map<String, dynamic>?> read() async {
    final encoded = await _storage.read(key: _key);
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Corrupt secure state is not a recoverable session.
    }
    await delete();
    return null;
  }

  @override
  Future<void> write(Map<String, dynamic> session) =>
      _storage.write(key: _key, value: jsonEncode(session));

  @override
  Future<void> delete() => _storage.delete(key: _key);
}
