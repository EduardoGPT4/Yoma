import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/models/favorite_entry.dart';
import 'package:yomashi/models/reading_progress.dart';
import 'package:yomashi/services/yoma_storage_migration.dart';

/// Rutas como las guarda Android; las carpetas reales son temporales.
const oldRoot = '/storage/emulated/0/YomaShi';
const newRoot = '/storage/emulated/0/Yoma/YomaShi';
String oldPath(List<String> parts) => p.posix.joinAll([oldRoot, ...parts]);
String newPath(List<String> parts) => p.posix.joinAll([newRoot, ...parts]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryStore store;
  late Directory phone;
  late String legacy, target;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
  });

  setUp(() async {
    phone = await Directory.systemTemp.createTemp('yoma_phone_');
    legacy = p.join(phone.path, 'YomaShi');
    target = p.join(phone.path, 'Yoma', 'YomaShi');
    await store.replaceProgressMap({});
    await store.replaceFavoritesMap({});
    await store.replaceReadChapterKeys({});
    await store.replaceRecords('reader', []);
    await store.replaceRecords('structured', []);
  });

  tearDown(() => phone.delete(recursive: true));

  Future<File> write(String relative, [String text = 'x']) async {
    final file = File(p.join(legacy, relative));
    await file.parent.create(recursive: true);
    return file.writeAsString(text);
  }

  Future<bool> run() => YomaStorageMigration.migrate(
    legacy: Directory(legacy),
    target: Directory(target),
    store: store,
    prefixes: [(oldRoot, newRoot)],
  );

  Future<void> seed() async {
    final manga = oldPath(['Manga', 'Dr. Stone']);
    final chapter = p.posix.join(manga, 'Capítulo 1');
    await store.upsertProgress(
      ReadingProgress(
        mangaPath: manga,
        mangaTitle: 'Dr. Stone',
        coverPath: p.posix.join(manga, 'cover.jpg'),
        chapterPath: chapter,
        chapterTitle: 'Capítulo 1',
        pageIndex: 7,
        updatedAt: 1,
      ),
    );
    // Un manga online se identifica por URL y no debe cambiar.
    await store.upsertProgress(
      const ReadingProgress(
        mangaPath: 'https://example.invalid/manga/1',
        mangaTitle: 'Online',
        chapterPath: 'https://example.invalid/manga/1/1',
        chapterTitle: '1',
        pageIndex: 0,
        updatedAt: 1,
      ),
    );
    await store.setChapterRead(chapter, true);
    await store.setFavorite(
      FavoriteEntry(
        key: manga,
        title: 'Dr. Stone',
        coverPath: p.posix.join(manga, 'cover.jpg'),
      ),
    );
    await store.putRecord('reader', manga, {'zoom': 2});
    await store.putRecord('structured', 'downloads', {
      'root': oldRoot,
      'folder': oldPath(['Manga']),
      'other': '${oldRoot}Otros/no-tocar',
    });
    SharedPreferences.setMockInitialValues({
      'download_root_v1': oldRoot,
      'library_paths': [
        oldPath(['Manga']),
        '/otra/carpeta',
      ],
      'active_manga_source_v1': 'mangadex',
    });
  }

  test(
    'moves the YomaShi folder into Yoma and rewrites every saved path',
    () async {
      await write(p.join('Manga', 'Dr. Stone', 'Capítulo 1', '001.jpg'));
      await write(p.join('Manga', '.nomedia'), '');
      await write(p.join('Backups', 'yomashi_backup_1.json'), '{}');
      await seed();

      expect(await run(), isTrue);

      expect(Directory(legacy).existsSync(), isFalse);
      expect(
        File(
          p.join(target, 'Manga', 'Dr. Stone', 'Capítulo 1', '001.jpg'),
        ).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(target, 'Backups', 'yomashi_backup_1.json')).existsSync(),
        isTrue,
      );

      final manga = newPath(['Manga', 'Dr. Stone']);
      final progress = await store.getProgressMap();
      expect(progress.keys, contains(manga));
      expect(progress[manga]!.pageIndex, 7);
      expect(progress[manga]!.chapterPath, p.posix.join(manga, 'Capítulo 1'));
      expect(progress[manga]!.coverPath, p.posix.join(manga, 'cover.jpg'));
      expect(progress.keys, contains('https://example.invalid/manga/1'));
      expect(await store.getReadChapterKeys(), {
        p.posix.join(manga, 'Capítulo 1'),
      });
      final favorite = (await store.getFavoritesMap())[manga]!;
      expect(favorite.coverPath, p.posix.join(manga, 'cover.jpg'));
      expect(await store.getRecord('reader', manga), {'zoom': 2});
      expect(await store.getRecord('structured', 'downloads'), {
        'root': newRoot,
        'folder': newPath(['Manga']),
        'other': '${oldRoot}Otros/no-tocar',
      });

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('download_root_v1'), newRoot);
      expect(prefs.getStringList('library_paths'), [
        newPath(['Manga']),
        '/otra/carpeta',
      ]);
      expect(prefs.getString('active_manga_source_v1'), 'mangadex');
    },
  );

  test('running again changes nothing', () async {
    await write(p.join('Manga', 'A', '1', '001.jpg'));
    await seed();
    await run();
    Future<Map<String, Map<String, dynamic>>> snapshot() async => {
      for (final e in (await store.getProgressMap()).entries)
        e.key: e.value.toMap(),
    };
    final before = await snapshot();
    expect(await run(), isFalse);
    expect(await snapshot(), before);
    expect(
      (await SharedPreferences.getInstance()).getString('download_root_v1'),
      newRoot,
    );
  });

  test(
    'an interrupted migration finishes rewriting on the next launch',
    () async {
      await seed();
      // Las carpetas ya se movieron, pero los datos siguen con la ruta anterior.
      await Directory(target).create(recursive: true);
      expect(await run(), isFalse);
      final manga = newPath(['Manga', 'Dr. Stone']);
      expect((await store.getProgressMap()).keys, contains(manga));
    },
  );

  test('merges into an existing Yoma folder without overwriting', () async {
    await write(p.join('Manga', 'A', '1', '001.jpg'), 'antiguo');
    await write(p.join('Manga', 'A', '2', '001.jpg'));
    await write(p.join('Manga', 'B', '1', '001.jpg'));
    final kept = File(p.join(target, 'Manga', 'A', '1', '001.jpg'));
    await kept.parent.create(recursive: true);
    await kept.writeAsString('nuevo');

    await run();

    expect(await kept.readAsString(), 'nuevo');
    expect(
      File(p.join(target, 'Manga', 'A', '2', '001.jpg')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(target, 'Manga', 'B', '1', '001.jpg')).existsSync(),
      isTrue,
    );
    // El archivo en conflicto se queda en su sitio anterior; nada se borra.
    expect(
      File(p.join(legacy, 'Manga', 'A', '1', '001.jpg')).readAsStringSync(),
      'antiguo',
    );
  });

  test('rejects folder prefixes that could match other paths', () async {
    expect(() => store.relocatePathPrefix('', newRoot), throwsArgumentError);
    expect(
      () => store.relocatePathPrefix('$oldRoot/', newRoot),
      throwsArgumentError,
    );
  });
}
