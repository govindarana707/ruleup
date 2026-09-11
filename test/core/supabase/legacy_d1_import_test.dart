import 'package:flutter_test/flutter_test.dart';

import '../../../tool/legacy_d1_import.dart';

const userId = '11111111-1111-4111-8111-111111111111';
const categoryId = '22222222-2222-4222-8222-222222222222';
const habitId = '33333333-3333-4333-8333-333333333333';
const ledgerId = '44444444-4444-4444-8444-444444444444';
const redemptionId = '55555555-5555-4555-8555-555555555555';
const rewardId = '77777777-7777-4777-8777-777777777777';

void main() {
  test('existing account import is idempotent', () async {
    final bundle = LegacyImportBundle.parse(_fixture());
    final target = _MemoryTarget();
    final importer = LegacyAccountImporter(target);

    expect(await importer.import(bundle), isTrue);
    expect(await importer.import(bundle), isFalse);
    expect(target.rows.length, 4);
    expect(target.rows['point_ledger/$ledgerId']?['source_id'], redemptionId);
    expect(target.rows['point_ledger/$ledgerId']?['reward_id'], rewardId);
  });

  test('interrupted import restarts without duplicate effects', () async {
    final bundle = LegacyImportBundle.parse(_fixture());
    final target = _MemoryTarget(interruptAfter: 2);
    await expectLater(
      LegacyAccountImporter(target).import(bundle),
      throwsStateError,
    );
    target.interruptAfter = null;
    expect(await LegacyAccountImporter(target).import(bundle), isTrue);
    expect(target.rows.length, 4);
  });

  test('cross-user and duplicate ledger source data is rejected', () {
    final crossUser = _fixture();
    (crossUser['tables'] as Map)['habits'][0]['user_id'] =
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    expect(() => LegacyImportBundle.parse(crossUser), throwsFormatException);

    final duplicate = _fixture();
    final tables = duplicate['tables'] as Map;
    final rows = List<dynamic>.from(tables['point_ledger'] as List);
    tables['point_ledger'] = rows;
    rows.add(
      Map<String, dynamic>.from(rows.single as Map)
        ..['id'] = '66666666-6666-4666-8666-666666666666',
    );
    expect(() => LegacyImportBundle.parse(duplicate), throwsFormatException);
  });

  test('legacy reward image is rewritten to an owner and reward path', () {
    final fixture = _fixture();
    final tables = fixture['tables'] as Map;
    final rewards = tables['rewards'] as List;
    const objectId = '88888888-8888-4888-8888-888888888888';
    final sourceKey = 'rewards/$userId/$objectId.jpg';
    (rewards.single as Map)['image_key'] = sourceKey;
    fixture['images'] = [
      {
        'reward_id': rewardId,
        'object_id': objectId,
        'source_key': sourceKey,
        'mime_type': 'image/jpeg',
        'sha256': List.filled(64, 'a').join(),
        'file': 'unused-by-parser.jpg',
      },
    ];

    final bundle = LegacyImportBundle.parse(fixture);
    final target = '$userId/$rewardId/$objectId.jpg';
    expect(bundle.images.single['target_key'], target);
    expect(bundle.tables['rewards']!.single['image_key'], target);
  });
}

Map<String, dynamic> _fixture() => {
  'user': {
    'id': userId,
    'username': 'existing_user',
    'supabase_auth_email': '$userId@auth.ruleup.invalid',
    'auth_migrated_at': '2026-09-10T10:00:00Z',
  },
  'tables': {
    'categories': [
      {
        'id': categoryId,
        'user_id': userId,
        'name': 'Health',
        'sort_order': 0,
        'created_at': '2026-09-01T10:00:00Z',
        'updated_at': '2026-09-01T10:00:00Z',
      },
    ],
    'habits': [
      {
        'id': habitId,
        'user_id': userId,
        'category_id': categoryId,
        'name': 'Walk',
        'measurement_type': 'yes_no',
        'sort_order': 0,
        'missed_penalty_enabled': false,
        'missed_penalty_points': 0,
        'created_at': '2026-09-01T10:00:00Z',
        'updated_at': '2026-09-01T10:00:00Z',
      },
    ],
    'habit_options': [],
    'habit_schedules': [],
    'point_rules': [],
    'check_ins': [],
    'habit_pauses': [],
    'rewards': [
      {
        'id': rewardId,
        'user_id': userId,
        'name': 'Coffee',
        'points_cost': 25,
        'monetary_cap': null,
        'image_key': null,
        'sort_order': 0,
        'created_at': '2026-09-01T10:00:00Z',
        'updated_at': '2026-09-01T10:00:00Z',
      },
    ],
    'habit_reminders': [],
    'point_ledger': [
      {
        'id': ledgerId,
        'user_id': userId,
        'source_type': 'reward_redemption',
        'source_id': redemptionId,
        'points': -25,
        'reason': 'Reward: Coffee',
        'created_at': '2026-09-02T10:00:00Z',
        'updated_at': '2026-09-02T10:00:00Z',
      },
    ],
  },
  'images': [],
};

class _MemoryTarget implements LegacyImportTarget {
  _MemoryTarget({this.interruptAfter});
  int? interruptAfter;
  String? hash;
  bool completed = false;
  int calls = 0;
  final rows = <String, Map<String, dynamic>>{};

  @override
  Future<void> verifyIdentity(Map<String, dynamic> user) async {}

  @override
  Future<ImportCheckpoint?> checkpoint(String userId) async =>
      hash == null ? null : ImportCheckpoint(hash!, completed: completed);

  @override
  Future<void> begin(LegacyImportBundle bundle) async => hash = bundle.hash;

  @override
  Future<void> putRow(String table, Map<String, dynamic> row) async {
    calls++;
    if (interruptAfter == calls) throw StateError('simulated interruption');
    final key = '$table/${row['id']}';
    final existing = rows[key];
    if (existing != null && existing.toString() != row.toString()) {
      throw StateError('conflict');
    }
    rows[key] = row;
  }

  @override
  Future<void> putImage(Map<String, dynamic> image) async {}

  @override
  Future<void> complete(LegacyImportBundle bundle) async => completed = true;
}
