import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/models/reading_progress.dart';
import 'package:yomashi/utils/archive_import.dart';
import 'package:yomashi/utils/backup_service.dart';
import 'package:yomashi/utils/fs_scanner.dart';
import 'package:yomashi/utils/preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late LibraryStore store;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('yomashi-backup-');
    await store.replaceProgressMap({});
    await store.replaceFavoritesMap({});
    await store.replaceReadChapterKeys({});
    await store.replaceRecords('categories', []);
    await store.replaceRecords('reader', []);
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  ReadingProgress progress(int date) => ReadingProgress(
    mangaPath: 'https://inmanga.com/manga/a',
    mangaTitle: 'A',
    chapterPath: 'https://inmanga.com/chapter/a',
    chapterTitle: 'Chapter',
    pageIndex: 3,
    updatedAt: date,
  );
  test('backup roundtrip includes categories and per-title settings', () async {
    await store.upsertProgress(progress(5));
    await PreferencesService.setCategories([
      {
        'id': 'group',
        'name': 'Reading',
        'mangaKeys': ['a'],
      },
    ]);
    await store.putRecord('reader', 'https://inmanga.com/a', {
      'direction': 'vertical',
      'fit': 'fitWidth',
      'zoom': true,
      'double': false,
      'continuous': true,
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('reader_free_zoom_v1', false);
    final file = await BackupService.exportToFile(directory: root);
    expect((await BackupService.preview(file)).categories, 1);
    await store.replaceProgressMap({});
    await store.replaceRecords('reader', []);
    await prefs.setBool('reader_free_zoom_v1', true);
    await BackupService.importFromFile(file, recoveryDirectory: root);
    expect(
      (await PreferencesService.getProgressMap()).values.single.updatedAt,
      5,
    );
    expect(
      (await PreferencesService.getCategories()).single['name'],
      'Reading',
    );
    expect(
      (await store.getRecord('reader', 'https://inmanga.com/a'))['continuous'],
      true,
    );
    expect(prefs.getBool('reader_free_zoom_v1'), false);
    expect(root.listSync().whereType<File>().length, 2);
  });
  test('invalid backup cannot partially replace existing records', () async {
    await store.upsertProgress(progress(10));
    final file = await BackupService.exportToFile(directory: root);
    final map = jsonDecode(await file.readAsString()) as Map;
    map['favorites'] = [
      {'key': 23},
    ];
    await file.writeAsString(jsonEncode(map));
    await expectLater(
      BackupService.importFromFile(file, recoveryDirectory: root),
      throwsA(anything),
    );
    expect(
      (await PreferencesService.getProgressMap()).values.single.updatedAt,
      10,
    );
    expect(root.listSync().whereType<File>().length, 1);
  });
  test(
    'merge keeps the newest progress and unions category assignments',
    () async {
      await store.upsertProgress(progress(1));
      await PreferencesService.setCategories([
        {
          'id': 'g',
          'name': 'Group',
          'mangaKeys': ['old'],
        },
      ]);
      final file = await BackupService.exportToFile(directory: root);
      await store.upsertProgress(progress(20));
      await PreferencesService.setCategories([
        {
          'id': 'g',
          'name': 'Group',
          'mangaKeys': ['new'],
        },
      ]);
      await BackupService.importFromFile(
        file,
        merge: true,
        recoveryDirectory: root,
      );
      expect(
        (await PreferencesService.getProgressMap()).values.single.updatedAt,
        20,
      );
      expect(
        (await PreferencesService.getCategories()).single['mangaKeys'],
        containsAll(['old', 'new']),
      );
    },
  );
  test('SQLite transaction rolls back related updates on failure', () async {
    await store.upsertProgress(progress(3));
    await expectLater(
      store.transaction(() async {
        await store.upsertProgress(progress(99));
        throw StateError('disk failure');
      }),
      throwsStateError,
    );
    expect(
      (await PreferencesService.getProgressMap()).values.single.updatedAt,
      3,
    );
  });
  test(
    'CBZ imports in natural order and never overwrites an existing book',
    () async {
      final archive = Archive();
      for (final name in ['10.gif', '2.png', '1.jpg']) {
        final bytes = utf8.encode(name);
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
      }
      final file = await File(
        '${root.path}/book.cbz',
      ).writeAsBytes(ZipEncoder().encode(archive));
      final first = await ArchiveImport.importCbzOrZip(
        archiveFile: file,
        destinationRoot: '${root.path}/library',
      );
      final second = await ArchiveImport.importCbzOrZip(
        archiveFile: file,
        destinationRoot: '${root.path}/library',
      );
      expect(first.path, isNot(second.path));
      final pages = FsScanner.loadChapterPages('${first.path}/Capitulo 001');
      expect(pages.length, 3);
      expect(await File(pages[0]).readAsString(), '1.jpg');
      expect(await File(pages[1]).readAsString(), '2.png');
      expect(await File(pages[2]).readAsString(), '10.gif');
    },
  );
}
