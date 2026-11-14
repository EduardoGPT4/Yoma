import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/models/favorite_entry.dart';
import 'package:yomashi/models/reading_progress.dart';
import 'package:yomashi/providers/chapter_read_provider.dart';
import 'package:yomashi/services/manga_sync.dart';
import 'package:yomashi/services/myanimelist_client.dart';

class _Credentials extends MalCredentialStore {
  Map<String, dynamic>? value;
  _Credentials(int owner)
    : value = {
        'device_token': 'device-$owner',
        'connected': true,
        'profile': {'id': owner, 'name': 'Tester'},
      };
  @override
  Future<Map<String, dynamic>?> load() async => value;
  @override
  Future<void> save(Map<String, dynamic> value) async => this.value = value;
  @override
  Future<void> clear() async => value = null;
}

/// Servidor en memoria con las reglas de yoma-sync.php.
class _Server {
  final rows = <String, Map<String, dynamic>>{};
  var kinds = ['anime', 'episode', 'manga', 'manga_progress', 'manga_read'];
  int rev = 0;
  int pushes = 0;

  Map<String, dynamic> handle(int owner, Map<String, dynamic> input) {
    switch (input['action']) {
      case 'sync_capabilities':
        return {'sync': 1, 'kinds': kinds};
      case 'sync_push':
        pushes++;
        var accepted = 0;
        for (final change in (input['changes'] as List).cast<Map>()) {
          expect(kinds, contains(change['kind']));
          expect(change['key'], matches(RegExp(r'^[a-f0-9]{40}$')));
          final id = '$owner|${change['kind']}|${change['key']}';
          final current = rows[id];
          if (current != null &&
              (current['updated_at'] as int) >= (change['updated_at'] as int)) {
            continue;
          }
          final deleted = change['deleted'] == true;
          rows[id] = {
            'owner': owner,
            'kind': change['kind'],
            'key': change['key'],
            // Como el servidor: un borrado viaja sin contenido.
            'payload': deleted ? <String, dynamic>{} : change['payload'],
            'updated_at': change['updated_at'],
            'deleted': deleted,
            'rev': ++rev,
          };
          accepted++;
        }
        return {'accepted': accepted, 'cursor': rev};
      default:
        final since = input['since'] as int;
        final changes =
            rows.values
                .where((r) => r['owner'] == owner && (r['rev'] as int) > since)
                .toList()
              ..sort((a, b) => (a['rev'] as int).compareTo(b['rev'] as int));
        return {
          'changes': changes,
          'cursor': changes.isEmpty ? rev : changes.last['rev'],
          'more': false,
        };
    }
  }
}

class _Client extends MyAnimeListClient {
  final _Server server;
  final int owner;
  _Client(this.server, this.owner) : super(credentials: _Credentials(owner));
  @override
  Future<Map<String, dynamic>> request(
    Map<String, dynamic> input, {
    bool anonymous = false,
    int? expectedOwner,
  }) async {
    expect(expectedOwner, owner);
    return server.handle(owner, input);
  }
}

class _Phone {
  final LibraryStore db;
  final MangaSync sync;
  _Phone(this.db, _Client client)
    : sync = MangaSync(client: client, database: () async => db);
}

const manga = 'https://mangadex.org/title/frieren';
const chapter1 = 'https://mangadex.org/chapter/c1';
const chapter2 = 'https://mangadex.org/chapter/c2';

ReadingProgress progress(int page, int at, {String path = manga}) =>
    ReadingProgress(
      mangaPath: path,
      mangaTitle: 'Frieren',
      coverPath: 'https://cdn.example/f.jpg',
      chapterPath: path == manga ? chapter2 : '$path/c1',
      chapterTitle: 'Capítulo 2',
      pageIndex: page,
      updatedAt: at,
      sourceId: 'mangadex',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Server server;
  _Phone phone({int owner = 7}) => _Phone(
    LibraryStore(AppDatabase.forTesting(NativeDatabase.memory())),
    _Client(server, owner),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    server = _Server();
  });

  test('biblioteca, progreso y leídos pasan al otro teléfono', () async {
    final a = phone(), b = phone();
    await a.db.setFavorite(
      const FavoriteEntry(
        key: manga,
        title: 'Frieren',
        coverPath: 'https://cdn.example/f.jpg',
      ),
    );
    await a.db.upsertProgress(progress(12, 1000));
    await a.db.setChapterRead(chapter1, true);
    // Un manga sin conexión (ruta del teléfono) no viaja.
    await a.db.setFavorite(
      const FavoriteEntry(key: '/storage/emulated/0/Manga/Local', title: 'L'),
    );
    await a.db.upsertProgress(progress(3, 1000, path: '/storage/Manga/Local'));
    final sent = await a.sync.sync();
    expect(sent.sent, 3);
    expect(await a.sync.pending(7), isEmpty);

    final notified = MangaSync.changes.value;
    final got = await b.sync.sync();
    expect(got.received, 3);
    expect(MangaSync.changes.value, notified + 1);
    final favorite = (await b.db.getFavoritesMap())[manga]!;
    expect(favorite.title, 'Frieren');
    expect(favorite.coverPath, 'https://cdn.example/f.jpg');
    final p = (await b.db.getProgressMap())[manga]!;
    expect((p.chapterPath, p.pageIndex, p.updatedAt), (chapter2, 12, 1000));
    expect(p.sourceId, 'mangadex');
    expect(await b.db.getReadChapterKeys(), {chapter1});
    expect((await b.db.getFavoritesMap()).keys, [manga]);
    // Lo recibido no se vuelve a subir.
    expect(await b.sync.pending(7), isEmpty);
  });

  test('quitar de la biblioteca y desmarcar viajan como borrados', () async {
    final a = phone(), b = phone();
    await a.db.setFavorite(const FavoriteEntry(key: manga, title: 'Frieren'));
    await a.db.setChapterRead(chapter1, true);
    await a.sync.sync();
    await b.sync.sync();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await a.db.removeFavorite(manga);
    await a.db.setChapterRead(chapter1, false);
    expect((await a.sync.sync()).sent, 2);
    expect((await b.sync.sync()).received, 2);
    expect(await b.db.getFavoritesMap(), isEmpty);
    expect(await b.db.getReadChapterKeys(), isEmpty);
    // Desmarcado: MyAnimeList no vuelve a marcarlo en ese teléfono.
    expect(
      await b.db.getRecord(ChapterReadProvider.unmarkedNamespace, chapter1),
      isNotNull,
    );
  });

  test('gana el cambio más reciente; lo de aquí más nuevo se queda', () async {
    final a = phone(), b = phone();
    await a.db.upsertProgress(progress(5, 1000));
    await b.db.upsertProgress(progress(40, 2000));
    await a.sync.sync();
    await b.sync.sync(); // B no aplica el de A (más antiguo) y sube el suyo.
    expect((await b.db.getProgressMap())[manga]!.pageIndex, 40);
    await a.sync.sync();
    expect((await a.db.getProgressMap())[manga]!.pageIndex, 40);

    // Leído aquí después de que otro lo desmarcara: se queda leído.
    await b.db.setChapterRead(chapter2, true);
    await b.sync.sync();
    await a.sync.sync();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await a.db.setChapterRead(chapter2, false);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await b.db.setChapterRead(chapter2, true);
    await a.sync.sync();
    await b.sync.sync();
    await a.sync.sync();
    for (final p in [a, b]) {
      expect(await p.db.getReadChapterKeys(), contains(chapter2));
    }
  });

  test('lo marcado como leído por MyAnimeList no se sube', () async {
    final a = phone();
    await a.db.setChapterRead(chapter1, true, sync: false);
    expect(await a.sync.pending(7), isEmpty);
  });

  test('las cuentas no se mezclan', () async {
    final a = phone(owner: 7), other = phone(owner: 8);
    await a.db.setFavorite(const FavoriteEntry(key: manga, title: 'Frieren'));
    await a.sync.sync();
    expect((await other.sync.sync()).received, 0);
    expect(await other.db.getFavoritesMap(), isEmpty);
  });

  test('con un servidor sin manga no sube nada ni falla', () async {
    final a = phone();
    await a.db.setFavorite(const FavoriteEntry(key: manga, title: 'Frieren'));
    server.kinds = ['anime', 'episode'];
    expect((await a.sync.sync()).ran, isFalse);
    expect(a.sync.unsupported, isTrue);
    expect(server.pushes, 0);
    // Con el servidor nuevo, reintentar sincroniza sin reiniciar.
    server.kinds = [...server.kinds, 'manga', 'manga_progress', 'manga_read'];
    final retried = await a.sync.sync(force: true);
    expect((retried.ran, retried.sent), (true, 1));
  });

  test('la huella es la misma en todos los dispositivos', () {
    // Primeros 40 caracteres del SHA-256 de la URL (como en yoma-sync.php).
    expect(
      MangaSync.key('https://mangadex.org/title/frieren'),
      matches(RegExp(r'^[a-f0-9]{40}$')),
    );
    expect(MangaSync.key(manga), MangaSync.key(manga));
    expect(MangaSync.key(manga), isNot(MangaSync.key(chapter1)));
  });
}
