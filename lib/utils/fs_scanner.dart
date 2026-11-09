import 'dart:convert';
import '../models/content_identity.dart';
import '../data/download_storage.dart';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../models/manga.dart';
import 'manga_storage.dart';
import 'sorting.dart';
import 'title_sanitizer.dart';

class FsScanner {
  static Future<void> writeLegacyIdentity(Manga manga) async {
    await DownloadStorage.writeJson(
      File(p.join(manga.path, DownloadStorage.mangaManifest)),
      {
        'id': ContentIdentity.id(manga.sourceUrl ?? manga.path),
        'title': manga.title,
        'url': manga.sourceUrl,
        'legacyLocalOnly': manga.sourceUrl == null,
      },
    );
    for (var i = 0; i < manga.chapters.length; i++) {
      final chapter = manga.chapters[i];
      if (await File(
        p.join(chapter.path, DownloadStorage.chapterManifest),
      ).exists()) {
        continue;
      }
      await DownloadStorage.writeJson(
        File(p.join(chapter.path, DownloadStorage.chapterManifest)),
        {
          ...chapter.toMap(),
          'order': i,
          'id': ContentIdentity.id(chapter.path),
          'legacy': true,
          'complete': false,
          'pages': loadChapterPages(chapter.path),
        },
      );
    }
  }

  static const Set<String> _extensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.image',
  };

  static Map<String, dynamic>? _manifest(Directory dir, String name) {
    final file = File(p.join(dir.path, name));
    if (!file.existsSync()) return null;
    try {
      return Map<String, dynamic>.from(
        jsonDecode(file.readAsStringSync()) as Map,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? scanMangaFolder(String path) =>
      _scanMangaMetadataMap(Directory(path));
  static Future<List<Manga>> scanLibraryMetadata(List<String> roots) async {
    final mangas = <Manga>[];

    for (final root in roots.toSet()) {
      final rootDir = Directory(root);
      if (!rootDir.existsSync()) {
        continue;
      }

      final mangaDirs = _safeListDirs(rootDir);
      mangaDirs.sort(
        (a, b) => naturalCompare(p.basename(a.path), p.basename(b.path)),
      );

      for (final mangaDir in mangaDirs) {
        final manga = _scanMangaMetadata(mangaDir);
        if (manga == null) {
          continue;
        }
        mangas.add(manga);
      }
    }

    mangas.sort((a, b) => naturalCompare(a.title, b.title));
    return mangas;
  }

  static Future<void> scanLibraryIncremental(
    Map<String, dynamic> message,
  ) async {
    final roots = (message['roots'] as List<dynamic>? ?? <dynamic>[])
        .cast<String>();
    final sendPort = message['sendPort'] as SendPort;

    try {
      final mangas = <Map<String, dynamic>>[];

      for (final root in roots.toSet()) {
        final rootDir = Directory(root);
        if (!rootDir.existsSync()) {
          continue;
        }

        final mangaDirs = _safeListDirs(rootDir);
        mangaDirs.sort(
          (a, b) => naturalCompare(p.basename(a.path), p.basename(b.path)),
        );

        for (final mangaDir in mangaDirs) {
          final manga = _scanMangaMetadataMap(mangaDir);
          if (manga == null) {
            continue;
          }
          mangas.add(manga);
          sendPort.send(<String, dynamic>{'type': 'item', 'manga': manga});
        }
      }

      mangas.sort(
        (a, b) => naturalCompare(
          a['title'] as String? ?? '',
          b['title'] as String? ?? '',
        ),
      );

      sendPort.send(<String, dynamic>{'type': 'done', 'mangas': mangas});
    } catch (error) {
      sendPort.send(<String, dynamic>{
        'type': 'error',
        'message': error.toString(),
      });
    }
  }

  static List<String> loadChapterPages(String chapterPath) {
    final manifest = _manifest(
      Directory(chapterPath),
      DownloadStorage.chapterManifest,
    );
    final expected = manifest?['pages'];
    if (manifest?['legacy'] != true &&
        expected is List &&
        expected.isNotEmpty) {
      // Conservar el índice original aunque una descarga parcial tenga huecos.
      return [
        for (var i = 0; i < expected.length; i++)
          DownloadStorage().pageFile(Directory(chapterPath), i).path,
      ];
    }
    final pages = <String>[];
    final files = _safeListFiles(Directory(chapterPath));

    for (final file in files) {
      final ext = p.extension(file.path).toLowerCase();
      if (_extensions.contains(ext)) {
        pages.add(file.path);
      }
    }

    pages.sort((a, b) => naturalCompare(p.basename(a), p.basename(b)));
    return pages;
  }

  static Manga? _scanMangaMetadata(Directory mangaDir) {
    final chapterDirs = _safeListDirs(mangaDir);
    chapterDirs.sort(
      (a, b) => naturalCompare(p.basename(a.path), p.basename(b.path)),
    );

    final chapters = <Map<String, dynamic>>[];
    for (final chapterDir in chapterDirs) {
      final chapter = _scanChapterMetadata(chapterDir);
      if (chapter != null) {
        chapters.add(chapter);
      }
    }

    chapters.sort((a, b) {
      final order = (a['order'] as int? ?? 0).compareTo(
        b['order'] as int? ?? 0,
      );
      return order != 0
          ? order
          : naturalCompare(a['title'] as String, b['title'] as String);
    });
    if (chapters.isEmpty) {
      return null;
    }

    return Manga.fromMap(<String, dynamic>{
      'title':
          _manifest(mangaDir, DownloadStorage.mangaManifest)?['title'] ??
          TitleSanitizer.clean(p.basename(mangaDir.path)),
      'sourceUrl': _manifest(mangaDir, DownloadStorage.mangaManifest)?['url'],
      'path': mangaDir.path,
      'coverPath': MangaStoragePaths.findMangaCoverPath(mangaDir.path),
      'chapters': chapters,
    });
  }

  static Map<String, dynamic>? _scanMangaMetadataMap(Directory mangaDir) =>
      _scanMangaMetadata(mangaDir)?.toMap();

  static Map<String, dynamic>? _scanChapterMetadata(Directory chapterDir) {
    final files = _safeListFiles(chapterDir);
    var pageCount = 0;
    String? coverPath;
    String? coverName;

    for (final file in files) {
      final ext = p.extension(file.path).toLowerCase();
      if (!_extensions.contains(ext)) {
        continue;
      }

      pageCount++;
      final baseName = p.basename(file.path);
      if (coverPath == null || naturalCompare(baseName, coverName ?? '') < 0) {
        coverPath = file.path;
        coverName = baseName;
      }
    }

    if (pageCount == 0) {
      return null;
    }

    final manifest = _manifest(chapterDir, DownloadStorage.chapterManifest);
    final expected = (manifest?['pages'] as List?)?.length;
    return <String, dynamic>{
      'title':
          manifest?['title'] ??
          TitleSanitizer.clean(p.basename(chapterDir.path)),
      'sourceUrl': manifest?['sourcePath'],
      'order': manifest?['order'],
      'number': manifest?['number'],
      'volume': manifest?['volume'],
      'language': manifest?['language'],
      'complete':
          (manifest?['complete'] as bool? ?? true) &&
          (expected == null || expected == pageCount),
      'path': chapterDir.path,
      'pageCount': expected ?? pageCount,
      'coverPath': coverPath,
    };
  }

  static List<Directory> _safeListDirs(Directory dir) {
    try {
      return dir
          .listSync(followLinks: false)
          .whereType<Directory>()
          .where((d) => !p.basename(d.path).startsWith('.yomashi-'))
          .toList();
    } catch (_) {
      return <Directory>[];
    }
  }

  static List<File> _safeListFiles(Directory dir) {
    try {
      return dir.listSync(followLinks: false).whereType<File>().toList();
    } catch (_) {
      return <File>[];
    }
  }
}
