import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/models/manga.dart';
import 'package:yomashi/services/myanimelist_client.dart';
import 'package:yomashi/services/myanimelist_service.dart';
import 'package:yomashi/utils/preferences.dart';
import 'package:yomashi/widgets/mal_sync_status.dart';

class _Credentials extends MalCredentialStore {
  Map<String, dynamic>? value = {
    'device_token': 'test',
    'connected': true,
    'profile': {'id': 1, 'name': 'Reader'},
  };
  @override
  Future<Map<String, dynamic>?> load() async => value;
  @override
  Future<void> save(Map<String, dynamic> value) async => this.value = value;
  @override
  Future<void> clear() async => value = null;
}

class _Client extends MyAnimeListClient {
  _Client() : super(credentials: _Credentials());
  int reads = 0;
  @override
  Future<MalManga> detail(int id) async {
    reads++;
    return MalManga(
      id: id,
      title: 'MAL obra',
      chaptersRead: 12,
      totalChapters: 100,
      status: 'reading',
      publishingStatus: 'publishing',
    );
  }
}

const chosen = MalManga(
  id: 7,
  title: 'MAL obra',
  chaptersRead: 3,
  totalChapters: 100,
  status: 'reading',
  publishingStatus: 'publishing',
);

const folder = '/storage/emulated/0/Yoma/YomaShi/Manga/Horizon';
const url = 'https://zonatmo.org/library/manga/1/horizon';

Manga offline(String title, {String path = folder, String? sourceUrl}) =>
    Manga(title: title, path: path, sourceUrl: sourceUrl, chapters: const []);

Manga online(String title, {String link = url}) =>
    Manga(title: title, path: link, sourceUrl: link, chapters: const []);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryStore store;
  late _Client client;
  late MyAnimeListService service;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
  });
  setUp(() async {
    for (final namespace in [
      'mal_links',
      'mal_pending',
      'mal_sync',
      'mal_unlinked',
      'mal_chapters',
    ]) {
      await store.replaceRecords(namespace, []);
    }
    await PreferencesService.setMangaSourceLinks({});
    client = _Client();
    service = MyAnimeListService(client);
  });
  tearDown(() {
    client.http.close(force: true);
    client.sessionChanges.dispose();
    service.changes.dispose();
  });

  test('vincular la copia descargada vincula la ficha online', () async {
    await PreferencesService.setMangaSourceLink(folder, url);
    await service.link(offline('Horizon'), chosen, automatic: true);
    final link = await service.linkFor(online('Horizon'));
    expect(link?['malId'], 7);
    // Se guarda con la URL online, la identidad de la obra.
    expect(link?['id'], MyAnimeListService.mangaKey(online('Horizon')));
    expect((await service.statusFor(online('Horizon')))['snapshot'], isNotNull);
  });

  test(
    'un vínculo antiguo guardado con la carpeta también se comparte',
    () async {
      await PreferencesService.setMangaSourceLink(folder, url);
      await store.putRecord('mal_links', folder, {
        'id': folder,
        'manga': folder,
        'title': 'Horizon',
        'malId': 7,
        'malTitle': 'MAL obra',
        'owner': 1,
        'automatic': true,
        'version': 1,
      });
      expect((await service.linkFor(online('Otro nombre')))?['malId'], 7);
      expect((await service.linkFor(offline('Horizon')))?['id'], folder);
    },
  );

  test(
    'una carpeta sin URL se une con la ficha online del mismo nombre',
    () async {
      await service.link(offline('HORIZON'), chosen, automatic: true);
      expect((await service.linkFor(online('Horizon')))?['malId'], 7);
      // Y al revés: vincular online se ve en la carpeta del mismo nombre.
      await service.unlink(online('Horizon'));
      expect(await service.linkFor(offline('HORIZON')), isNull);
      expect(await service.unlinkedByUser(offline('HORIZON')), isTrue);
    },
  );

  test('vincular online se ve en una carpeta local del mismo nombre', () async {
    await service.link(online('Horizon'), chosen, automatic: true);
    expect(
      (await service.linkFor(offline('Horizon')))?['id'],
      MyAnimeListService.mangaKey(online('Horizon')),
    );
  });

  test('no se une por nombre si hay dudas', () async {
    // Dos carpetas vinculadas con el mismo nombre.
    await service.link(offline('Horizon'), chosen, automatic: true);
    await service.link(
      offline('Horizon', path: '/storage/emulated/0/Otra/Horizon'),
      chosen,
      automatic: true,
    );
    expect(await service.linkFor(online('Horizon')), isNull);
  });

  test('una carpeta descargada de otra fuente no se une por nombre', () async {
    await PreferencesService.setMangaSourceLink(
      folder,
      'https://mangadex.org/title/otra',
    );
    await store.putRecord('mal_links', folder, {
      'id': folder,
      'manga': folder,
      'title': 'Horizon',
      'malId': 7,
      'owner': 1,
      'automatic': true,
      'version': 1,
    });
    expect(await service.linkFor(online('Horizon')), isNull);
    expect(
      (await service.linkFor(
        online('Horizon', link: 'https://mangadex.org/title/otra'),
      ))?['malId'],
      7,
    );
  });

  test('no se une por nombre una obra cuyo vínculo quitó el usuario', () async {
    await service.link(online('Horizon'), chosen, automatic: true);
    await service.unlink(online('Horizon'));
    await service.link(offline('Horizon'), chosen, automatic: true);
    expect(await service.linkFor(online('Horizon')), isNull);
    expect(await service.unlinkedByUser(online('Horizon')), isTrue);
  });

  testWidgets('el estado de MAL se consulta solo, sin botón', (tester) async {
    await tester.runAsync(
      () => service.link(online('Horizon'), chosen, automatic: false),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MalSyncStatus(manga: online('Horizon'), service: service),
        ),
      ),
    );
    for (var i = 0; i < 20 && client.reads == 0; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    // El vínculo nuevo ya trae su consulta: no se repite enseguida.
    expect(client.reads, 0);
    // Una consulta antigua se renueva al abrir la ficha.
    await tester.runAsync(() async {
      final key = await MyAnimeListService.keyFor(online('Horizon'));
      final row = Map<String, dynamic>.from(
        await store.getRecord('mal_sync', key) as Map,
      );
      await store.putRecord('mal_sync', key, {...row, 'checkedAt': 1});
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MalSyncStatus(manga: online('Horizon'), service: service),
        ),
      ),
    );
    for (
      var i = 0;
      i < 40 && !find.textContaining('capítulo 12').evaluate().isNotEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(client.reads, 1);
    expect(find.textContaining('capítulo 12'), findsOneWidget);
    expect(find.text('Consultar estado en MAL'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
