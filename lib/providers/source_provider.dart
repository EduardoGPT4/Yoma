import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

import '../models/manga_source.dart';
import '../services/mangadex_service.dart';
import '../services/online_catalog_service.dart';
import '../utils/preferences.dart';

/// Fuente online activa y lista de fuentes disponibles.
class SourceProvider extends ChangeNotifier {
  MangaSource _active = MangaSources.byId(MangaSources.defaultId);
  bool _loaded = false;
  bool _dataSaver = false;
  bool get dataSaver => _dataSaver;
  Future<void> setDataSaver(bool value) async {
    _dataSaver = value;
    MangaDexService.dataSaver = value;
    await (await SharedPreferences.getInstance()).setBool(
      'mangadex_data_saver',
      value,
    );
    notifyListeners();
  }

  List<String> _mangaDexLanguages = List<String>.from(
    MangaDexLanguage.defaultCodes,
  );

  MangaSource get active => _active;
  String get activeId => _active.id;
  bool get isLoaded => _loaded;
  List<MangaSource> get sources => MangaSources.all;

  /// Idiomas MangaDex activos, también usados por búsquedas y capítulos.
  List<String> get mangaDexLanguages =>
      List<String>.unmodifiable(_mangaDexLanguages);

  /// True si la fuente actual puede usarse para explorar/descargar.
  bool get isActiveImplemented => _active.implemented;

  Future<void> load() async {
    _dataSaver =
        (await SharedPreferences.getInstance()).getBool(
          'mangadex_data_saver',
        ) ??
        false;
    MangaDexService.dataSaver = _dataSaver;
    final stored = await PreferencesService.getActiveMangaSourceId();
    if (stored == 'hitomi') {
      await PreferencesService.setActiveMangaSourceId(MangaSources.defaultId);
    } else if (stored != null && stored.isNotEmpty) {
      _active = MangaSources.byId(stored);
      if (stored == 'yupmanga' && _active.id == 'manhwaweb') {
        await PreferencesService.setActiveMangaSourceId('manhwaweb');
      }
    }

    final langs = await PreferencesService.getMangaDexLanguages();
    _mangaDexLanguages = MangaDexLanguage.normalizeCodes(langs);
    MangaDexService.setPreferredLanguages(_mangaDexLanguages);

    OnlineCatalogService.setActiveSourceId(_active.id);
    _loaded = true;
    notifyListeners();
  }

  Future<void> select(String sourceId) async {
    if (sourceId == 'hitomi') return;
    final next = MangaSources.byId(sourceId);
    await PreferencesService.setActiveMangaSourceId(next.id);
    OnlineCatalogService.setActiveSourceId(next.id);
    if (next.id == _active.id) {
      return;
    }
    _active = next;
    notifyListeners();
  }

  /// Activa/desactiva un idioma de capítulos de MangaDex.
  /// Debe quedar al menos uno seleccionado.
  Future<void> toggleMangaDexLanguage(String code) async {
    code = code.trim().toLowerCase();
    if (!MangaDexLanguage.supports(code)) return;
    final next = List<String>.from(_mangaDexLanguages);
    if (next.contains(code)) {
      if (next.length <= 1) {
        return;
      }
      next.remove(code);
    } else {
      next.add(code);
    }
    // Orden estable: es, es-la, resto.
    next.sort((a, b) {
      const order = ['es', 'es-la'];
      final ai = order.indexOf(a);
      final bi = order.indexOf(b);
      if (ai == -1 && bi == -1) {
        return a.compareTo(b);
      }
      if (ai == -1) {
        return 1;
      }
      if (bi == -1) {
        return -1;
      }
      return ai.compareTo(bi);
    });

    _mangaDexLanguages = next;
    MangaDexService.setPreferredLanguages(_mangaDexLanguages);
    notifyListeners();
    await PreferencesService.setMangaDexLanguages(_mangaDexLanguages);
  }

  bool isMangaDexLanguageEnabled(String code) =>
      _mangaDexLanguages.contains(code);
}
