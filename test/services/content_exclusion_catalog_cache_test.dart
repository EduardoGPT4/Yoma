import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/models/online_manga.dart';
import 'package:yomashi/utils/catalog_cache.dart';

const _item = OnlineMangaSummary(
  title: 'Stored fixture',
  url: 'fixture://catalog/1',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryStore store;
  late AppDatabase database;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase.forTesting(NativeDatabase.memory());
    store = await LibraryStore.initialize(database: database);
  });
  setUp(() async => store.replaceRecords('catalog', []));
  tearDownAll(() async => database.close());

  Map<String, dynamic> cached() => {
    'savedAt': DateTime.now().millisecondsSinceEpoch,
    'items': [_item.toMap()],
  };

  test(
    'catalogs saved under older exclusion rules are not shown as fresh',
    () async {
      for (final section in ['home', 'feed']) {
        await store.putRecord('catalog', 'hitomi:spanish:$section', cached());
        await store.putRecord(
          'catalog',
          'hitomi:spanish:$section:exclusions=[]',
          cached(),
        );
      }
      expect(
        await CatalogCache.loadHome(sourceId: 'hitomi', languageKey: 'spanish'),
        isEmpty,
      );
      expect(
        await CatalogCache.loadUpdated(
          sourceId: 'hitomi',
          languageKey: 'spanish',
        ),
        isEmpty,
      );
      expect(
        await CatalogCache.savedAt(sourceId: 'hitomi', languageKey: 'spanish'),
        isNull,
      );
      expect(
        await CatalogCache.isFresh(sourceId: 'hitomi', languageKey: 'spanish'),
        isFalse,
      );
    },
  );

  test('catalog and feed saved with current rules remain available', () async {
    await CatalogCache.saveHome(
      [_item],
      sourceId: 'hitomi',
      languageKey: 'spanish',
    );
    await CatalogCache.saveUpdated(
      [_item],
      sourceId: 'hitomi',
      languageKey: 'spanish',
    );
    expect(
      (await CatalogCache.loadHome(
        sourceId: 'hitomi',
        languageKey: 'spanish',
      )).single.title,
      _item.title,
    );
    expect(
      (await CatalogCache.loadUpdated(
        sourceId: 'hitomi',
        languageKey: 'spanish',
      )).single.url,
      _item.url,
    );
    expect(
      await CatalogCache.isFresh(sourceId: 'hitomi', languageKey: 'spanish'),
      isTrue,
    );
  });

  test('existing MangaDex cache keys are preserved', () async {
    await store.putRecord('catalog', 'mangadex:en:home', cached());
    expect(
      (await CatalogCache.loadHome(
        sourceId: 'mangadex',
        languageKey: 'en',
      )).single.title,
      _item.title,
    );
    expect(
      await CatalogCache.isFresh(sourceId: 'mangadex', languageKey: 'en'),
      isTrue,
    );
  });
}
