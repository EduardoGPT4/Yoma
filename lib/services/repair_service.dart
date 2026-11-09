import 'dart:io';
import 'package:path/path.dart' as p;
import '../data/download_storage.dart';
import '../models/online_manga.dart';
import '../utils/app_failure.dart';

class RepairReport {
  final OnlineMangaDetail detail;
  final String root;
  final Set<int> damaged;
  final int checkedPages, missingPages;
  const RepairReport(
    this.detail,
    this.root,
    this.damaged,
    this.checkedPages,
    this.missingPages,
  );
}

class RepairService {
  static Future<RepairReport> inspect(String folder) async {
    final directory = Directory(folder);
    final data = await DownloadStorage.readJson(
      File(p.join(folder, DownloadStorage.mangaManifest)),
    );
    if (data == null || data['url'] is! String) {
      throw const AppFailure(
        FailureKind.storage,
        'Esta carpeta no tiene información de origen verificable. Vincula la obra antes de repararla.',
      );
    }
    final detail = OnlineMangaDetail.fromMap(data);
    final storage = DownloadStorage();
    final damaged = <int>{};
    var checked = 0, missing = 0;
    for (var i = 0; i < detail.chapters.length; i++) {
      final chapter = storage.chapterFolder(directory, detail.chapters[i]);
      final manifest = await DownloadStorage.readJson(
        File(p.join(chapter.path, DownloadStorage.chapterManifest)),
      );
      // Solo se revisa lo que el usuario descargó, sin bajar capítulos nuevos.
      if (manifest == null) continue;
      final pages = (manifest['pages'] as List? ?? []).cast<String>();
      final good = await storage.verifiedPages(chapter, pages);
      checked += pages.length;
      missing += pages.length - good.length;
      if (pages.isEmpty ||
          good.length != pages.length ||
          manifest['complete'] != true) {
        damaged.add(i);
      }
    }
    final root = directory.parent.parent.path;
    if (p.normalize(storage.mangaFolder(root, detail).absolute.path) !=
        p.normalize(directory.absolute.path)) {
      throw const AppFailure(
        FailureKind.storage,
        'La carpeta heredada requiere migración de identidad antes de repararse. Sus archivos se conservan.',
      );
    }
    return RepairReport(detail, root, damaged, checked, missing);
  }
}
