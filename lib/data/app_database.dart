import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class ReadingProgressRows extends Table {
  TextColumn get mangaPath => text()();
  TextColumn get mangaTitle => text()();
  TextColumn get coverPath => text().nullable()();
  TextColumn get chapterPath => text()();
  TextColumn get chapterTitle => text()();
  IntColumn get pageIndex => integer()();
  IntColumn get updatedAt => integer()();
  TextColumn get sourceId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {mangaPath};
}

class ReadChapterRows extends Table {
  TextColumn get chapterPath => text()();

  @override
  Set<Column<Object>> get primaryKey => {chapterPath};
}

class FavoriteRows extends Table {
  TextColumn get mangaKey => text()();
  TextColumn get title => text()();
  TextColumn get coverPath => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {mangaKey};
}

@DriftDatabase(tables: [ReadingProgressRows, ReadChapterRows, FavoriteRows])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'yomashi'));

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;
  Future<void> _records() => customStatement(
    'CREATE TABLE IF NOT EXISTS app_records (namespace TEXT NOT NULL, record_key TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(namespace, record_key))',
  );
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _records();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) await _records();
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA busy_timeout = 5000');
      await customStatement('PRAGMA journal_mode = WAL');
      await _records();
    },
  );
}
