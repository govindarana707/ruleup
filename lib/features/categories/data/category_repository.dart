import 'package:drift/drift.dart';
import 'package:ruleup/core/database/app_database.dart';
import 'package:ruleup/core/sync/sync_service.dart';

class CategoryRepository {
  CategoryRepository(this._database, this._sync);

  final AppDatabase _database;
  final SyncService _sync;

  Future<Category> create({
    required String userId,
    required String name,
    int sortOrder = 0,
  }) => _database.transaction(() async {
    final category = await _database
        .into(_database.categories)
        .insertReturning(
          CategoriesCompanion.insert(
            userId: userId,
            name: _validName(name),
            sortOrder: Value(sortOrder),
          ),
        );
    await _enqueue(category, 'create');
    return category;
  });

  Future<Category?> getById(String userId, String id) {
    final query = _database.select(_database.categories)
      ..where((row) => row.id.equals(id) & row.userId.equals(userId));
    return query.getSingleOrNull();
  }

  Future<List<Category>> list(String userId, {bool includeArchived = false}) {
    final query = _database.select(_database.categories)
      ..where(
        (row) =>
            row.userId.equals(userId) &
            (includeArchived ? const Constant(true) : row.archivedAt.isNull()),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.sortOrder),
        (row) => OrderingTerm.asc(row.name),
        (row) => OrderingTerm.asc(row.createdAt),
      ]);
    return query.get();
  }

  Future<Category?> update({
    required String userId,
    required String id,
    required String name,
    required int sortOrder,
  }) => _database.transaction(() async {
    final existing = await getById(userId, id);
    if (existing == null) return null;
    await (_database.update(
      _database.categories,
    )..where((row) => row.id.equals(id) & row.userId.equals(userId))).write(
      CategoriesCompanion(
        name: Value(_validName(name)),
        sortOrder: Value(sortOrder),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
    final updated = await getById(userId, id);
    await _enqueue(updated!, 'update');
    return updated;
  });

  Future<bool> archive(String userId, String id) =>
      _database.transaction(() async {
        final existing = await getById(userId, id);
        if (existing == null) return false;
        if (existing.archivedAt != null) return true;
        final now = DateTime.now().toUtc();
        await (_database.update(
          _database.categories,
        )..where((row) => row.id.equals(id) & row.userId.equals(userId))).write(
          CategoriesCompanion(archivedAt: Value(now), updatedAt: Value(now)),
        );
        await _enqueue(existing, 'archive');
        return true;
      });

  Future<void> _enqueue(Category category, String operation) => _sync.enqueue(
    userId: category.userId,
    entityType: 'category',
    entityId: category.id,
    operation: operation,
  );

  String _validName(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) throw ArgumentError.value(name, 'name');
    return normalized;
  }
}
