import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const importOrder = <String>[
  'categories',
  'habits',
  'habit_options',
  'habit_schedules',
  'point_rules',
  'check_ins',
  'habit_pauses',
  'rewards',
  'habit_reminders',
  'point_ledger',
];

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Validated, canonical snapshot exported from D1. Sessions, password hashes,
/// and D1 sync sequence numbers are intentionally never accepted.
class LegacyImportBundle {
  LegacyImportBundle._(this.user, this.tables, this.images, this.hash);

  factory LegacyImportBundle.parse(Object? input) {
    if (input is! Map) throw const FormatException('Bundle must be an object.');
    final root = Map<String, dynamic>.from(input);
    final userValue = root['user'];
    final tableValue = root['tables'];
    final imageValue = root['images'] ?? const <Object>[];
    if (userValue is! Map || tableValue is! Map || imageValue is! List) {
      throw const FormatException(
        'Bundle user, tables, or images are invalid.',
      );
    }
    final user = Map<String, dynamic>.from(userValue);
    final userId = _requiredString(user, 'id');
    final username = _requiredString(user, 'username');
    if (!_uuid.hasMatch(userId) ||
        !RegExp(r'^[a-z0-9_]{3,30}$').hasMatch(username) ||
        user['supabase_auth_email'] != '$userId@auth.ruleup.invalid' ||
        user['auth_migrated_at'] is! String) {
      throw const FormatException(
        'User has not completed the identity migration.',
      );
    }
    DateTime.parse(user['auth_migrated_at'] as String);

    final tables = <String, List<Map<String, dynamic>>>{};
    for (final table in importOrder) {
      final value = tableValue[table] ?? const <Object>[];
      if (value is! List) throw FormatException('$table must be an array.');
      final ids = <String>{};
      tables[table] = value
          .map((raw) {
            if (raw is! Map) {
              throw FormatException('$table row must be an object.');
            }
            final row = Map<String, dynamic>.from(raw);
            final id = _requiredString(row, 'id');
            if (!_uuid.hasMatch(id) || !ids.add(id)) {
              throw FormatException('$table has an invalid or duplicate id.');
            }
            if (row['user_id'] != userId) {
              throw FormatException('$table contains cross-user data.');
            }
            for (final key in ['created_at', 'updated_at']) {
              if (row[key] != null) DateTime.parse(row[key] as String);
            }
            return row;
          })
          .toList(growable: false);
    }
    _validateReferences(tables);
    _validateFinancialIdentity(tables);

    final images = imageValue
        .map((raw) {
          if (raw is! Map) {
            throw const FormatException('Image must be an object.');
          }
          final image = Map<String, dynamic>.from(raw);
          final rewardId = _requiredString(image, 'reward_id');
          final objectId = _requiredString(image, 'object_id');
          final mime = _requiredString(image, 'mime_type');
          final digest = _requiredString(image, 'sha256');
          if (!_uuid.hasMatch(rewardId) ||
              !_uuid.hasMatch(objectId) ||
              !{'image/jpeg', 'image/webp'}.contains(mime) ||
              !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
            throw const FormatException('Image metadata is invalid.');
          }
          final rewards = tables['rewards']!;
          final matching = rewards
              .where((row) => row['id'] == rewardId)
              .toList();
          if (matching.length != 1) {
            throw const FormatException(
              'Image references another account or reward.',
            );
          }
          final extension = mime == 'image/webp' ? 'webp' : 'jpg';
          final sourceKey = 'rewards/$userId/$objectId.$extension';
          if (image['source_key'] != sourceKey ||
              matching.single['image_key'] != sourceKey) {
            throw const FormatException(
              'Reward image reference is inconsistent.',
            );
          }
          final targetKey =
              '$userId/$rewardId/$objectId.${mime == 'image/webp' ? 'webp' : 'jpg'}';
          image['target_key'] = targetKey;
          matching.single['image_key'] = targetKey;
          return image;
        })
        .toList(growable: false);

    final canonical = jsonEncode({
      'user': _sortedMap(user),
      'tables': {for (final table in importOrder) table: tables[table]},
      'images': images,
    });
    return LegacyImportBundle._(
      user,
      tables,
      images,
      sha256.convert(utf8.encode(canonical)).toString(),
    );
  }

  final Map<String, dynamic> user;
  final Map<String, List<Map<String, dynamic>>> tables;
  final List<Map<String, dynamic>> images;
  final String hash;

  int get rowCount =>
      tables.values.fold(0, (total, rows) => total + rows.length);
}

abstract interface class LegacyImportTarget {
  Future<void> verifyIdentity(Map<String, dynamic> user);
  Future<ImportCheckpoint?> checkpoint(String userId);
  Future<void> begin(LegacyImportBundle bundle);
  Future<void> putRow(String table, Map<String, dynamic> row);
  Future<void> putImage(Map<String, dynamic> image);
  Future<void> complete(LegacyImportBundle bundle);
}

class ImportCheckpoint {
  const ImportCheckpoint(this.hash, {required this.completed});
  final String hash;
  final bool completed;
}

class LegacyAccountImporter {
  const LegacyAccountImporter(this.target);
  final LegacyImportTarget target;

  /// Every write uses a stable identity. Re-running after any interruption is
  /// safe; a different snapshot for the same account is rejected.
  Future<bool> import(LegacyImportBundle bundle) async {
    await target.verifyIdentity(bundle.user);
    final existing = await target.checkpoint(bundle.user['id'] as String);
    if (existing != null && existing.hash != bundle.hash) {
      throw StateError('Account already has a different import snapshot.');
    }
    if (existing?.completed ?? false) return false;
    await target.begin(bundle);
    for (final table in importOrder) {
      for (final row in bundle.tables[table]!) {
        await target.putRow(table, row);
      }
    }
    for (final image in bundle.images) {
      await target.putImage(image);
    }
    await target.complete(bundle);
    return true;
  }
}

class SupabaseRestImportTarget implements LegacyImportTarget {
  SupabaseRestImportTarget(
    this.baseUrl,
    this.serviceKey, {
    this.dryRun = false,
  });
  final Uri baseUrl;
  final String serviceKey;
  final bool dryRun;
  final HttpClient _client = HttpClient();

  Map<String, String> get _headers => {
    'apikey': serviceKey,
    'authorization': 'Bearer $serviceKey',
    'content-type': 'application/json',
  };

  @override
  Future<void> verifyIdentity(Map<String, dynamic> user) async {
    final response = await _request(
      'GET',
      '/auth/v1/admin/users/${user['id']}',
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final metadata = body['app_metadata'];
    if (body['id'] != user['id'] ||
        body['email'] != user['supabase_auth_email'] ||
        metadata is! Map ||
        metadata['identity_source'] != 'ruleup_legacy' ||
        metadata['legacy_user_id'] != user['id']) {
      throw StateError('Supabase Auth identity does not match the D1 account.');
    }
    final profileResponse = await _request(
      'GET',
      '/rest/v1/profiles?id=eq.${user['id']}&select=id,username',
    );
    final profiles = jsonDecode(profileResponse.body) as List;
    if (profiles.length != 1 ||
        profiles.single['username'] != user['username']) {
      throw StateError('Supabase profile does not match the D1 account.');
    }
  }

  @override
  Future<ImportCheckpoint?> checkpoint(String userId) async {
    final response = await _request(
      'GET',
      '/rest/v1/legacy_import_runs?user_id=eq.$userId&select=bundle_hash,status',
    );
    final rows = jsonDecode(response.body) as List;
    if (rows.isEmpty) return null;
    return ImportCheckpoint(
      rows.single['bundle_hash'] as String,
      completed: rows.single['status'] == 'completed',
    );
  }

  @override
  Future<void> begin(LegacyImportBundle bundle) async {
    if (dryRun) return;
    await _request(
      'POST',
      '/rest/v1/legacy_import_runs?on_conflict=user_id',
      body: jsonEncode({
        'user_id': bundle.user['id'],
        'bundle_hash': bundle.hash,
        'status': 'in_progress',
        'row_counts': {
          for (final e in bundle.tables.entries) e.key: e.value.length,
        },
      }),
      extraHeaders: {'Prefer': 'resolution=merge-duplicates'},
    );
  }

  @override
  Future<void> putRow(String table, Map<String, dynamic> row) async {
    final id = row['id'];
    final response = await _request(
      'GET',
      '/rest/v1/$table?id=eq.$id&select=*',
    );
    final rows = jsonDecode(response.body) as List;
    if (rows.isNotEmpty) {
      final current = Map<String, dynamic>.from(rows.single as Map);
      if (current['user_id'] != row['user_id']) {
        throw StateError('$table/$id belongs to another account.');
      }
      for (final entry in row.entries) {
        if (!_equivalent(entry.key, current[entry.key], entry.value)) {
          throw StateError('$table/$id conflicts with the import snapshot.');
        }
      }
      return;
    }
    if (!dryRun) {
      await _request('POST', '/rest/v1/$table', body: jsonEncode(row));
    }
  }

  @override
  Future<void> putImage(Map<String, dynamic> image) async {
    final path = image['file'] as String?;
    if (path == null) {
      throw const FormatException('Image file path is required.');
    }
    final file = File(path);
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > 1024 * 1024) {
      throw const FormatException('Image is empty or exceeds 1 MB.');
    }
    if (sha256.convert(bytes).toString() != image['sha256']) {
      throw const FormatException(
        'Image checksum does not match the snapshot.',
      );
    }
    final isJpeg =
        bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff;
    final isWebp =
        bytes.length >= 12 &&
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP';
    if ((image['mime_type'] == 'image/jpeg' && !isJpeg) ||
        (image['mime_type'] == 'image/webp' && !isWebp)) {
      throw const FormatException(
        'Image bytes do not match the declared MIME.',
      );
    }
    if (dryRun) return;
    await _request(
      'POST',
      '/storage/v1/object/reward-images/${image['target_key']}',
      bytes: bytes,
      extraHeaders: {
        'content-type': image['mime_type'] as String,
        'x-upsert': 'true',
      },
    );
  }

  @override
  Future<void> complete(LegacyImportBundle bundle) async {
    if (dryRun) return;
    await _request(
      'PATCH',
      '/rest/v1/legacy_import_runs?user_id=eq.${bundle.user['id']}',
      body: jsonEncode({
        'status': 'completed',
        'completed_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  Future<({int status, String body})> _request(
    String method,
    String path, {
    String? body,
    List<int>? bytes,
    Map<String, String> extraHeaders = const {},
  }) async {
    final request = await _client.openUrl(method, baseUrl.resolve(path));
    final headers = {..._headers, ...extraHeaders};
    headers.forEach(request.headers.set);
    if (body != null) request.write(body);
    if (bytes != null) request.add(bytes);
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        '$method $path failed (${response.statusCode}): $text',
      );
    }
    return (status: response.statusCode, body: text);
  }
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/legacy_d1_import.dart <bundle.json> [--dry-run]',
    );
    exitCode = 64;
    return;
  }
  final url = Platform.environment['SUPABASE_URL'];
  final key = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];
  if (url == null || key == null) {
    throw StateError('Supabase admin environment is required.');
  }
  final bundle = LegacyImportBundle.parse(
    jsonDecode(await File(args.first).readAsString()),
  );
  final imported = await LegacyAccountImporter(
    SupabaseRestImportTarget(
      Uri.parse(url),
      key,
      dryRun: args.contains('--dry-run'),
    ),
  ).import(bundle);
  stdout.writeln(
    imported
        ? 'Imported ${bundle.rowCount} rows (${bundle.hash}).'
        : 'Already imported (${bundle.hash}).',
  );
}

String _requiredString(Map<String, dynamic> value, String key) {
  final result = value[key];
  if (result is! String || result.isEmpty) {
    throw FormatException('$key is required.');
  }
  return result;
}

Map<String, dynamic> _sortedMap(Map<String, dynamic> value) => Map.fromEntries(
  value.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
);

String _jsonValue(Object? value) => jsonEncode(value);

bool _equivalent(String key, Object? left, Object? right) {
  if (left is num && right is num) return left == right;
  if (key.endsWith('_at') && left is String && right is String) {
    return DateTime.tryParse(left)?.toUtc() ==
        DateTime.tryParse(right)?.toUtc();
  }
  return _jsonValue(left) == _jsonValue(right);
}

void _validateReferences(Map<String, List<Map<String, dynamic>>> tables) {
  final categories = tables['categories']!.map((r) => r['id']).toSet();
  final habits = tables['habits']!.map((r) => r['id']).toSet();
  final options = tables['habit_options']!.map((r) => r['id']).toSet();
  final rules = tables['point_rules']!.map((r) => r['id']).toSet();
  for (final habit in tables['habits']!) {
    if (habit['category_id'] != null &&
        !categories.contains(habit['category_id'])) {
      throw const FormatException('Habit references an unavailable category.');
    }
  }
  for (final table in [
    'habit_options',
    'habit_schedules',
    'point_rules',
    'check_ins',
    'habit_pauses',
    'habit_reminders',
  ]) {
    for (final row in tables[table]!) {
      if (!habits.contains(row['habit_id'])) {
        throw FormatException('$table references another account or habit.');
      }
    }
  }
  for (final checkIn in tables['check_ins']!) {
    if (checkIn['option_id'] != null &&
        !options.contains(checkIn['option_id'])) {
      throw const FormatException('Check-in option is invalid.');
    }
    if (checkIn['matched_rule_id'] != null &&
        !rules.contains(checkIn['matched_rule_id'])) {
      throw const FormatException('Check-in rule is invalid.');
    }
  }
}

void _validateFinancialIdentity(
  Map<String, List<Map<String, dynamic>>> tables,
) {
  final sources = <String>{};
  final rewards = tables['rewards']!;
  final checkIns = {
    for (final checkIn in tables['check_ins']!) checkIn['id']: checkIn,
  };
  final habitIds = tables['habits']!.map((habit) => habit['id']).toSet();
  for (final row in tables['point_ledger']!) {
    final type = _requiredString(row, 'source_type');
    final source = _requiredString(row, 'source_id');
    if (!{'check_in', 'missed_check_in', 'reward_redemption'}.contains(type) ||
        !sources.add('$type:$source')) {
      throw const FormatException(
        'Ledger source identity is invalid or duplicated.',
      );
    }
    if (type == 'reward_redemption' && ((row['points'] as num?) ?? 0) >= 0) {
      throw const FormatException('Reward redemption must be a debit.');
    }
    if (type == 'reward_redemption') {
      final suppliedRewardId = row['reward_id'];
      if (suppliedRewardId == null) {
        final points = -((row['points'] as num).toInt());
        final reason = row['reason'];
        final matches = rewards
            .where(
              (reward) =>
                  reward['points_cost'] == points &&
                  reason == 'Reward: ${reward['name']}',
            )
            .toList();
        if (matches.length != 1) {
          throw const FormatException(
            'Reward redemption cannot be linked unambiguously.',
          );
        }
        row['reward_id'] = matches.single['id'];
      } else if (!rewards.any((reward) => reward['id'] == suppliedRewardId)) {
        throw const FormatException(
          'Reward redemption references another account or reward.',
        );
      }
    } else if (type == 'check_in') {
      final checkIn = checkIns[source];
      if (checkIn == null || checkIn['awarded_points'] != row['points']) {
        throw const FormatException(
          'Check-in ledger effect does not match its owned check-in.',
        );
      }
    } else {
      final parts = source.split(':');
      if (parts.length != 2 ||
          !habitIds.contains(parts.first) ||
          DateTime.tryParse(parts.last) == null ||
          ((row['points'] as num?) ?? 1) > 0) {
        throw const FormatException(
          'Missed check-in ledger effect is malformed.',
        );
      }
    }
  }
}
