import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/chapter.dart';
import '../models/content_identity.dart';
import '../models/online_manga.dart';
import '../services/image_repository.dart';
import '../utils/app_failure.dart';

class DownloadStorage {
  static const mangaManifest = 'manga.yomashi.json';
  static const chapterManifest = 'chapter.yomashi.json';
  static String safeName(String title) {
    final safe = title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    return safe.isEmpty || safe == '.' || safe == '..'
        ? 'Manga'
        : safe.substring(0, safe.length.clamp(0, 90));
  }

  Directory mangaFolder(String root, OnlineMangaDetail manga) => Directory(
    p.join(root, 'Manga', 'manga-${ContentIdentity.id(manga.url)}'),
  );
  Directory chapterFolder(Directory manga, Chapter chapter) => Directory(
    p.join(manga.path, 'chapter-${ContentIdentity.id(chapter.path)}'),
  );
  File pageFile(Directory chapter, int index) => File(
    p.join(chapter.path, '${(index + 1).toString().padLeft(5, '0')}.image'),
  );
  Future<Map<String, String>> chapterStates(
    String root,
    OnlineMangaDetail manga,
  ) async {
    final folder = mangaFolder(root, manga);
    final states = <String, String>{};
    for (final chapter in manga.chapters) {
      final directory = chapterFolder(folder, chapter);
      final data = await readJson(
        File(p.join(directory.path, chapterManifest)),
      );
      if (data == null) continue;
      final pages = (data['pages'] as List?)?.cast<String>() ?? [];
      final verified = await verifiedPages(directory, pages);
      states[chapter.path] =
          pages.isNotEmpty &&
              verified.length == pages.length &&
              data['complete'] == true
          ? 'Descargado'
          : 'Parcial (${verified.length}/${pages.length})';
    }
    return states;
  }

  Future<void> saveManga(Directory folder, OnlineMangaDetail manga) async {
    await folder.create(recursive: true);
    final file = File(p.join(folder.path, mangaManifest));
    final old = await readJson(file);
    if (old?['url'] is String &&
        ContentIdentity.canonical(old!['url'] as String) !=
            ContentIdentity.canonical(manga.url)) {
      throw const AppFailure(
        FailureKind.storage,
        'Se detectó una colisión de identidad en la carpeta.',
      );
    }
    // Una ficha paginada no debe hacer desaparecer capítulos ya descargados.
    final known = <String, Map<String, dynamic>>{
      for (final c in old?['chapters'] as List? ?? [])
        if (c is Map && c['path'] is String)
          c['path'] as String: Map<String, dynamic>.from(c),
      for (final c in manga.chapters) c.path: c.toMap(),
    };
    await writeJson(file, {
      ...manga.toMap(),
      'chapters': known.values.toList(),
    });
  }

  Future<void> saveChapter(
    Directory folder,
    Chapter chapter,
    int order,
    List<String> pages, {
    required bool complete,
  }) async {
    await folder.create(recursive: true);
    final file = File(p.join(folder.path, chapterManifest));
    final old = await readJson(file);
    if (old?['sourcePath'] is String &&
        ContentIdentity.canonical(old!['sourcePath'] as String) !=
            ContentIdentity.canonical(chapter.path)) {
      throw const AppFailure(
        FailureKind.storage,
        'Se detectó una colisión de capítulo.',
      );
    }
    await writeJson(file, {
      ...chapter.toMap(),
      'order': order,
      'pages': pages,
      'complete': complete,
      'sourcePath': chapter.path,
    });
  }

  Future<Set<int>> verifiedPages(Directory folder, List<String> urls) async {
    final good = <int>{};
    final manifest = await readJson(File(p.join(folder.path, chapterManifest)));
    final expected = (manifest?['pages'] as List?)?.cast<String>();
    for (var i = 0; i < urls.length; i++) {
      final file = pageFile(folder, i);
      if (expected != null &&
          i < expected.length &&
          (expected[i] == urls[i] ||
              (manifest?['sourcePath']?.toString().contains(
                        'mangadex.org/chapter/',
                      ) ==
                      true &&
                  Uri.tryParse(expected[i])?.path ==
                      Uri.tryParse(urls[i])?.path)) &&
          await ImageRepository.valid(file)) {
        good.add(i);
      }
    }
    return good;
  }

  static Future<Map<String, dynamic>?> readJson(File file) async {
    if (!await file.exists()) return null;
    try {
      final value = jsonDecode(await file.readAsString());
      return value is Map ? Map<String, dynamic>.from(value) : null;
    } catch (error) {
      throw AppFailure(
        FailureKind.storage,
        'Manifiesto dañado: ${file.path}',
        cause: error,
      );
    }
  }

  static Future<void> writeJson(File file, Map<String, dynamic> value) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(value), flush: true);
    await temp.rename(file.path);
  }
}
