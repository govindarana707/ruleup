import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/database/tables/habits.dart';
import 'package:ruleup/core/sync/sync_service.dart';
import 'package:ruleup/core/sync/sync_transport.dart';
import 'package:ruleup/features/categories/data/category_repository.dart';
import 'package:ruleup/features/habits/data/habit_repository.dart';

void main() {
  late AppDatabase database;
  late CategoryRepository categories;
  late HabitRepository habits;
  late String userId;
  late String otherUserId;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final sync = SyncService(database, const _UnusedTransport());
    categories = CategoryRepository(database, sync);
    habits = HabitRepository(database, sync);
    userId = await _createUser(database);
    otherUserId = await _createUser(database);
  });

  tearDown(() => database.close());

  test('category CRUD writes locally and enqueues sync', () async {
    final created = await categories.create(
      userId: userId,
      name: ' Health ',
      sortOrder: 2,
    );
    expect(created.name, 'Health');
    expect(created.id, isNotEmpty);

    final updated = await categories.update(
      userId: userId,
      id: created.id,
      name: 'Wellbeing',
      sortOrder: 1,
    );
    expect(updated?.name, 'Wellbeing');
    expect((await categories.getById(userId, created.id))?.sortOrder, 1);

    final queue = await database.select(database.syncQueue).get();
    expect(
      queue.map((item) => item.operation),
      containsAll(['create', 'update']),
    );
    expect(queue.every((item) => item.userId == userId), isTrue);
  });

  test('categories are ordered and archived instead of deleted', () async {
    final later = await categories.create(
      userId: userId,
      name: 'Later',
      sortOrder: 2,
    );
    final first = await categories.create(
      userId: userId,
      name: 'First',
      sortOrder: 1,
    );
    expect((await categories.list(userId)).map((item) => item.id), [
      first.id,
      later.id,
    ]);

    expect(await categories.archive(userId, first.id), isTrue);
    expect(await categories.list(userId), hasLength(1));
    final archived = await categories.getById(userId, first.id);
    expect(archived?.archivedAt, isNotNull);
    expect(await categories.list(userId, includeArchived: true), hasLength(2));
  });

  test('habit CRUD supports category and measurement types', () async {
    final category = await categories.create(userId: userId, name: 'Fitness');
    final habit = await habits.create(
      userId: userId,
      categoryId: category.id,
      name: 'Run',
      measurementType: MeasurementType.duration,
      sortOrder: 2,
    );
    final updated = await habits.update(
      userId: userId,
      id: habit.id,
      categoryId: null,
      name: 'Steps',
      measurementType: MeasurementType.count,
      sortOrder: 1,
    );

    expect(updated?.categoryId, isNull);
    expect(updated?.measurementType, MeasurementType.count);
    expect((await habits.getById(userId, habit.id))?.name, 'Steps');

    final yesNo = await habits.create(
      userId: userId,
      name: 'Done',
      measurementType: MeasurementType.yesNo,
    );
    final storedType = await database
        .customSelect(
          'SELECT measurement_type FROM habits WHERE id = ?',
          variables: [Variable(yesNo.id)],
        )
        .getSingle();
    expect(storedType.read<String>('measurement_type'), 'yes_no');
  });

  test('habits are ordered and archived instead of deleted', () async {
    final later = await habits.create(
      userId: userId,
      name: 'Later',
      measurementType: MeasurementType.yesNo,
      sortOrder: 3,
    );
    final first = await habits.create(
      userId: userId,
      name: 'First',
      measurementType: MeasurementType.value,
      sortOrder: 1,
    );
    expect((await habits.list(userId)).map((item) => item.id), [
      first.id,
      later.id,
    ]);

    expect(await habits.archive(userId, first.id), isTrue);
    expect(await habits.list(userId), hasLength(1));
    expect((await habits.getById(userId, first.id))?.archivedAt, isNotNull);
  });

  test('repositories prevent cross-user reads and writes', () async {
    final category = await categories.create(userId: userId, name: 'Private');
    final habit = await habits.create(
      userId: userId,
      categoryId: category.id,
      name: 'Private habit',
      measurementType: MeasurementType.yesNo,
    );

    expect(await categories.getById(otherUserId, category.id), isNull);
    expect(await categories.archive(otherUserId, category.id), isFalse);
    expect(await habits.getById(otherUserId, habit.id), isNull);
    expect(await habits.archive(otherUserId, habit.id), isFalse);
    await expectLater(
      habits.create(
        userId: otherUserId,
        categoryId: category.id,
        name: 'Invalid',
        measurementType: MeasurementType.yesNo,
      ),
      throwsArgumentError,
    );
  });

  test('archive operations enqueue category and habit sync items', () async {
    final category = await categories.create(userId: userId, name: 'Category');
    final habit = await habits.create(
      userId: userId,
      name: 'Habit',
      measurementType: MeasurementType.yesNo,
    );
    await categories.archive(userId, category.id);
    await habits.archive(userId, habit.id);

    final archiveItems = await (database.select(
      database.syncQueue,
    )..where((row) => row.operation.equals('archive'))).get();
    expect(archiveItems.map((item) => item.entityType).toSet(), {
      'category',
      'habit',
    });
  });
}

Future<String> _createUser(AppDatabase database) async =>
    (await database
            .into(database.localUsers)
            .insertReturning(LocalUsersCompanion.insert()))
        .id;

class _UnusedTransport implements SyncTransport {
  const _UnusedTransport();
  @override
  Future<void> send(SyncQueueData item) => throw UnimplementedError();
}
