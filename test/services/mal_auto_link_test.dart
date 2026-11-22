import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/models/manga.dart';
import 'package:yomashi/services/mal_auto_link.dart';
import 'package:yomashi/services/myanimelist_client.dart';
import 'package:yomashi/services/myanimelist_service.dart';

import 'anime_mal_test.dart' show Credentials;

Map<String, dynamic> _manga(
  int id,
  String title, {
  List<String> alternatives = const [],
}) => {
  'id': id,
  'title': title,
  'chapters_read': 0,
  'num_chapters': 0,
  'status': 'plan_to_read',
  'publishing_status': 'currently_publishing',
  'alternative_titles': alternatives,
};

/// MAL simulado: búsqueda y ficha. No es MyAnimeList.
class SearchMal extends MyAnimeListClient {
  SearchMal(Credentials credentials) : super(credentials: credentials);
  final actions = <String>[];
  final Map<String, List<Map<String, dynamic>>> searches = {
    'Boku Girl': [_manga(10, 'Boku Girl'), _manga(11, 'Boku no Hero')],
    'Kanojo Okarishimasu': [
      // La búsqueda no trae títulos alternativos; la ficha sí.
      _manga(20, 'Kanojo, Okarishimasu Special'),
      _manga(21, 'Kanojo, Okarishimasu'),
    ],
    'Rent a Girlfriend': [
      _manga(30, 'Kanojo, Okarishimasu'),
      _manga(31, 'Rent-A-Girlfriend Anthology'),
    ],
    'Twins': [_manga(40, 'Twins'), _manga(41, 'TWINS!')],
  };
  final Map<int, Map<String, dynamic>> details = {
    30: _manga(30, 'Kanojo, Okarishimasu', alternatives: ['Rent-A-Girlfriend']),
    31: _manga(31, 'Rent-A-Girlfriend Anthology'),
  };

  @override
  Future<Map<String, dynamic>> request(
    Map<String, dynamic> input, {
    bool anonymous = false,
    int? expectedOwner,
  }) async {
    actions.add('${input['action']}');
    if (input['action'] == 'search') {
      return {'items': searches[input['query']] ?? const []};
    }
    if (input['action'] == 'detail') {
      return {'manga': details[input['id']] ?? _manga(input['id'] as int, '?')};
    }
    return {};
  }
}

Manga _local(String title) =>
    Manga(title: title, path: 'https://inmanga.com/$title', chapters: const []);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryStore db;
  late SearchMal server;
  late MalAutoLink auto;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    db = await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
  });

  setUp(() async {
    for (final ns in [
      MalAutoLink.namespace,
      MyAnimeListService.unlinkedNamespace,
      'mal_links',
      'mal_pending',
      'mal_sync',
      'mal_chapters',
    ]) {
      await db.replaceRecords(ns, []);
    }
    server = SearchMal(Credentials());
    auto = MalAutoLink(MyAnimeListService(server), database: () async => db);
  });
  tearDown(() => server.http.close(force: true));

  test('vincula con el único resultado del mismo nombre', () async {
    final manga = _local('Boku Girl');
    expect(await auto.run([manga]), 1);
    final link = await auto.service.linkFor(manga);
    expect(link!['malId'], 10);
    expect(link['automatic'], true);
  });

  test('no vincula si el nombre no coincide exactamente', () async {
    final manga = _local('Kanojo Okarishimasu');
    // «Kanojo, Okarishimasu» coincide sin contar signos.
    expect(await auto.run([manga]), 1);
    expect((await auto.service.linkFor(manga))!['malId'], 21);

    final other = _local('Kanojo Okarishimasu 2');
    expect(await auto.run([other]), 0);
    expect(await auto.service.linkFor(other), isNull);
  });

  test('usa los títulos alternativos de la ficha', () async {
    final manga = _local('Rent a Girlfriend');
    expect(await auto.run([manga]), 1);
    expect((await auto.service.linkFor(manga))!['malId'], 30);
    expect(server.actions.where((a) => a == 'detail'), isNotEmpty);
  });

  test('dos obras con el mismo nombre: no elige ninguna', () async {
    final manga = _local('Twins');
    expect(await auto.run([manga]), 0);
    expect(await auto.service.linkFor(manga), isNull);
  });

  test('respeta el desvinculado manual y no repite búsquedas', () async {
    final manga = _local('Boku Girl');
    await auto.run([manga]);
    await auto.service.unlink(manga);
    await db.replaceRecords(MalAutoLink.namespace, []);
    server.actions.clear();
    expect(await auto.run([manga]), 0);
    expect(server.actions, isNot(contains('search')));

    final fresh = _local('Kanojo Okarishimasu 2');
    await auto.run([fresh]);
    server.actions.clear();
    await auto.run([fresh]);
    expect(server.actions, isNot(contains('search')));
  });
}
