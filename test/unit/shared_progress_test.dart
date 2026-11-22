import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/models/chapter.dart';
import 'package:yomashi/models/manga.dart';
import 'package:yomashi/models/manga_source.dart';
import 'package:yomashi/models/reading_progress.dart';
import 'package:yomashi/providers/library_provider.dart';

ReadingProgress _progress({
  required String manga,
  required String title,
  required String chapter,
  required String chapterTitle,
  required int page,
  required int at,
}) => ReadingProgress(
  mangaPath: manga,
  mangaTitle: title,
  chapterPath: chapter,
  chapterTitle: chapterTitle,
  pageIndex: page,
  updatedAt: at,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
  });

  test('la clave de título ignora signos, acentos y mayúsculas', () {
    expect(
      LibraryProvider.titleKey('Boku Girl'),
      LibraryProvider.titleKey('BOKUGIRL!'),
    );
    expect(
      LibraryProvider.titleKey('Ver Mágico Online Gratis'),
      LibraryProvider.titleKey('magico'),
    );
    expect(
      LibraryProvider.titleKey('Boku Girl'),
      isNot(LibraryProvider.titleKey('Boku no Hero')),
    );
  });

  test('el progreso de otra fuente sirve si es el más reciente', () async {
    final library = LibraryProvider();
    await library.updateProgress(
      _progress(
        manga: 'https://inmanga.com/ver/manga/Boku-Girl/1',
        title: 'Boku Girl',
        chapter: 'https://inmanga.com/ver/manga/Boku-Girl/10/a',
        chapterTitle: 'Capítulo 10',
        page: 4,
        at: 1000,
      ),
    );
    await library.updateProgress(
      _progress(
        manga: 'https://zonatmo.to/manga/boku-girl',
        title: 'Bokugirl',
        chapter: 'https://zonatmo.to/manga/boku-girl/12',
        chapterTitle: 'Capítulo 12',
        page: 7,
        at: 2000,
      ),
    );

    final shared = library.progressFor(
      'https://inmanga.com/ver/manga/Boku-Girl/1',
      'Boku Girl',
    );
    expect(shared?.chapterTitle, 'Capítulo 12');

    // Un descargado de InManga retoma en el capítulo 12 por número.
    final downloaded = Manga(
      path: '/storage/Yoma/Manga/Boku Girl',
      title: 'Boku Girl',
      sourceUrl: 'https://inmanga.com/ver/manga/Boku-Girl/1',
      chapters: [
        for (final n in [10, 11, 12, 13])
          Chapter(
            path: '/storage/Yoma/Manga/Boku Girl/$n',
            title: 'Capítulo $n',
            pageCount: 20,
            complete: true,
          ),
      ],
    );
    final resume = library.resumePosition(downloaded);
    expect(resume.chapterIndex, 2);
    expect(resume.pageIndex, 7);
    library.dispose();
  });

  test('el capítulo se encuentra por enlace, título o número', () {
    final progress = _progress(
      manga: 'a',
      title: 'A',
      chapter: 'https://otra.fuente/cap/5',
      chapterTitle: 'Cap. 5.5',
      page: 0,
      at: 1,
    );
    final chapters = [
      (ref: 'https://x/1', title: 'Capítulo 5'),
      (ref: 'https://x/2', title: 'Capítulo 005.5 - Extra'),
    ];
    expect(LibraryProvider.chapterIndexFor(progress, chapters), 1);
    expect(LibraryProvider.chapterIndexFor(progress, [chapters.first]), -1);
  });

  test('cada fuente tiene su color y la carpeta sin fuente es gris', () {
    final ids = [
      'inmanga',
      'lectortmo',
      'zonatmo_to',
      'mangadex',
      'manhwaweb',
      'leercapitulo',
      'mangaoni',
      'mangalect',
      'hitomi',
    ];
    final colors = ids.map(MangaSources.color).toSet();
    expect(colors, hasLength(ids.length));
    expect(MangaSources.label(null), 'Carpeta local');
    expect(MangaSources.label('inmanga'), 'InManga');
  });
}
