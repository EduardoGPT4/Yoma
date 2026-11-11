import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/models/chapter.dart';
import 'package:yomashi/models/favorite_entry.dart';
import 'package:yomashi/models/manga.dart';
import 'package:yomashi/providers/chapter_read_provider.dart';
import 'package:yomashi/services/mal_reading_sync.dart';
import 'package:yomashi/services/myanimelist_client.dart';
import 'package:yomashi/services/myanimelist_service.dart';

import 'anime_mal_test.dart' show Credentials;

/// MAL simulado con la lista «Reading». No es MyAnimeList.
class ReadingMal extends MyAnimeListClient {
  ReadingMal(Credentials credentials) : super(credentials: credentials);
  final reading = <Map<String, dynamic>>[
    manga(1, 'Uno', read: 5, total: 20),
    manga(2, 'Dos', read: 3, alternatives: ['Two']),
  ];
  final actions = <String>[];
  bool offline = false;

  static Map<String, dynamic> manga(
    int id,
    String title, {
    int read = 0,
    int total = 0,
    List<String> alternatives = const [],
  }) => {
    'id': id,
    'title': title,
    'chapters_read': read,
    'num_chapters': total,
    'status': 'reading',
    'publishing_status': 'currently_publishing',
    'alternative_titles': alternatives,
  };

  @override
  Future<Map<String, dynamic>> request(
    Map<String, dynamic> input, {
    bool anonymous = false,
    int? expectedOwner,
  }) async {
    actions.add('${input['action']}');
    if (offline) throw const MalFailure('Sin conexión de prueba.');
    if (input['action'] == 'library') {
      return {'items': input['status'] == 'reading' ? reading : const []};
    }
    if (input['action'] == 'update') {
      return {
        'manga': {
          ...reading.first,
          'id': input['id'],
          'chapters_read': input['chapters_read'],
        },
      };
    }
    return {};
  }
}

List<Chapter> chapters(String base, Iterable<String> numbers) => [
  for (final n in numbers)
    Chapter(title: 'Capítulo $n', path: '$base/$n', number: n),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryStore db;
  late Credentials credentials;
  late ReadingMal server;
  late MalReadingSync sync;
  late ChapterReadProvider reads;

  final local = Manga(
    title: 'Uno',
    path: '/storage/emulated/0/Yoma/YomaShi/Manga/Uno',
    chapters: chapters('/storage/emulated/0/Yoma/YomaShi/Manga/Uno', [
      for (var i = 1; i <= 8; i++) '$i',
    ]),
  );

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    db = await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
  });
  setUp(() async {
    for (final ns in [
      MalReadingSync.namespace,
      ChapterReadProvider.unmarkedNamespace,
      'mal_links',
      'mal_pending',
      'mal_sync',
      'mal_chapters',
    ]) {
      await db.replaceRecords(ns, []);
    }
    await db.replaceReadChapterKeys({});
    credentials = Credentials();
    server = ReadingMal(credentials);
    sync = MalReadingSync(MyAnimeListService(server), database: () async => db);
    reads = ChapterReadProvider();
    await reads.load();
  });
  tearDown(() {
    reads.dispose();
    server.http.close(force: true);
  });

  List<String> read(Manga manga) => [
    for (final chapter in manga.chapters)
      if (reads.isRead(chapter.path)) chapter.number!,
  ];

  test('los capítulos leídos en MAL quedan leídos en YomaShi', () async {
    await sync.run([local], reads);
    expect(read(local), ['1', '2', '3', '4', '5']);
    // Vinculado automáticamente y con envío activado.
    final link = await sync.service.linkFor(local);
    expect(link!['malId'], 1);
    expect(link['automatic'], true);
    // Ya estaban en MAL: no se reenvían.
    expect(server.actions.where((a) => a == 'update'), isEmpty);
    expect(await db.readRecords('mal_pending'), isEmpty);

    // Se guarda en el teléfono.
    final reopened = ChapterReadProvider();
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.isRead('${local.path}/5'), isTrue);
    expect(reopened.isRead('${local.path}/6'), isFalse);
  });

  test('un capítulo que el usuario desmarcó no se vuelve a marcar', () async {
    await sync.run([local], reads);
    await reads.markUnread('${local.path}/3');
    await sync.run([local], reads);
    expect(read(local), ['1', '2', '4', '5']);
    // Se recuerda tras reiniciar.
    final reopened = ChapterReadProvider();
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.isUnmarked('${local.path}/3'), isTrue);
    // Marcarlo otra vez quita la marca.
    await reads.markRead('${local.path}/3');
    expect(reads.isUnmarked('${local.path}/3'), isFalse);
  });

  test('al abrir la ficha online se marcan sus capítulos', () async {
    const url = 'https://inmanga.com/manga/dos';
    final online = chapters(url, ['1', '2', '2.5', '3', '4']);
    final marked = await sync.apply(
      Manga(title: 'Two', path: url, sourceUrl: url, chapters: const []),
      online,
      reads,
    );
    // Coincide por un título alternativo de MAL; el 2.5 no tiene número
    // entero confirmado y no se marca.
    expect(marked, 3);
    expect(
      [
        for (final c in online)
          if (reads.isRead(c.path)) c.number,
      ],
      ['1', '2', '3'],
    );
    expect(
      (await sync.service.linkFor(online.first.toManga(url)))!['malId'],
      2,
    );
  });

  test(
    'los favoritos sin capítulos se vinculan y esperan a la ficha',
    () async {
      const url = 'https://inmanga.com/manga/uno';
      final candidates = MalReadingSync.candidates(
        favorites: [const FavoriteEntry(key: url, title: 'Uno')],
      );
      await sync.run(candidates, reads);
      expect(
        (await sync.service.linkFor(
          Manga(title: 'Uno', path: url, sourceUrl: url, chapters: const []),
        ))!['malId'],
        1,
      );
      expect(reads.totalReadChapters, 0);
    },
  );

  test('no se vincula con nombres dudosos ni con otra obra', () async {
    // Dos obras de la lista con el mismo nombre.
    server.reading.add(ReadingMal.manga(3, 'Uno'));
    expect(
      MalReadingSync.match(local, [
        for (final row in server.reading) MalManga.fromMap(row),
      ]),
      isNull,
    );
    server.reading.removeLast();
    // Más capítulos en el teléfono que los que la obra tiene en MAL.
    final long = Manga(
      title: 'Uno',
      path: '/x/uno',
      chapters: chapters('/x/uno', [for (var i = 1; i <= 40; i++) '$i']),
    );
    await sync.run([long], reads);
    expect(await sync.service.linkFor(long), isNull);
    expect(reads.totalReadChapters, 0);
    // Un nombre distinto no coincide.
    final other = Manga(title: 'Uno Dos', path: '/x/otro', chapters: const []);
    await sync.run([other], reads);
    expect(await sync.service.linkFor(other), isNull);
  });

  test('un vínculo existente se respeta y usa su obra', () async {
    await sync.service.link(
      local,
      MalManga.fromMap(ReadingMal.manga(2, 'Dos', read: 3)),
      automatic: false,
    );
    await sync.run([local], reads);
    expect((await sync.service.linkFor(local))!['malId'], 2);
    expect(read(local), ['1', '2', '3']);
  });

  test('una obra fuera de «Reading» no marca nada', () async {
    server.reading.removeAt(0);
    await sync.run([local], reads);
    expect(read(local), isEmpty);
  });

  test('la lista se guarda y sirve sin conexión', () async {
    await sync.run([local], reads);
    final calls = server.actions.where((a) => a == 'library').length;
    await sync.run([local], reads);
    expect(server.actions.where((a) => a == 'library').length, calls);
    // Sin conexión y forzando, se usa la copia guardada.
    server.offline = true;
    final list = await sync.reading(force: true);
    expect(list.map((m) => m.id), [1, 2]);
    // Otra cuenta no ve esta copia.
    server.offline = false;
    credentials.value = {
      'connected': true,
      'device_token': 'otra',
      'profile': {'id': 8},
    };
    server.reading
      ..clear()
      ..add(ReadingMal.manga(9, 'Nueve', read: 1));
    expect((await sync.reading()).map((m) => m.id), [9]);
  });

  test('sin cuenta conectada no hace nada', () async {
    credentials.value = null;
    await sync.run([local], reads);
    expect(server.actions, isEmpty);
    expect(reads.totalReadChapters, 0);
  });
}

extension on Chapter {
  Manga toManga(String url) =>
      Manga(title: 'Two', path: url, sourceUrl: url, chapters: const []);
}
