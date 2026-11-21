import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/models/reading_progress.dart';
import 'package:yomashi/providers/library_provider.dart';
import 'package:yomashi/utils/title_sanitizer.dart';

ReadingProgress _progress(String chapter, int page) => ReadingProgress(
  mangaPath: 'https://example.com/manga/a',
  mangaTitle: 'A',
  chapterPath: chapter,
  chapterTitle: chapter,
  pageIndex: page,
  updatedAt: DateTime.now().millisecondsSinceEpoch,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
  });

  test('pasar páginas del mismo capítulo avisa una sola vez', () async {
    final library = LibraryProvider();
    var notices = 0;
    library.addListener(() => notices++);

    await library.updateProgress(_progress('c1', 0));
    expect(notices, 1, reason: 'un capítulo nuevo avisa enseguida');

    notices = 0;
    for (var page = 1; page <= 5; page++) {
      await library.updateProgress(_progress('c1', page));
      await library.recordPageRead();
    }
    expect(notices, 0);
    expect(library.getProgress('https://example.com/manga/a')?.pageIndex, 5);

    await Future<void>.delayed(const Duration(milliseconds: 1700));
    expect(notices, 1, reason: 'al detenerse llega un aviso agrupado');
    expect(library.readingStats.pagesRead, 5);

    notices = 0;
    await library.updateProgress(_progress('c2', 0));
    expect(notices, 1);
    library.dispose();
  });

  test('el título limpio se reutiliza y sigue siendo correcto', () {
    const raw = 'Ver BLACK MOOON Online Gratis';
    expect(TitleSanitizer.clean(raw), 'BLACK MOOON');
    expect(
      identical(TitleSanitizer.clean(raw), TitleSanitizer.clean(raw)),
      true,
    );
  });
}
