import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/library_store.dart';
import '../models/favorite_entry.dart';
import '../models/reader_settings_enums.dart';
import '../models/reading_progress.dart';
import '../models/reading_stats.dart';

class PreferencesService {
  static const _keyLibraryPaths = 'library_paths';
  static const _keyReadingStats = 'reading_stats_v1';
  static const _keyCategories = 'categories_v1';
  static const _keyWifiOnlyDownloads = 'wifi_only_downloads_v1';
  static const _keyDownloadThreads = 'download_threads_v1';
  static const _keyDownloadSpeedLimitKbps = 'download_speed_limit_kbps_v1';
  static const _keyOnboardingCompleted = 'onboarding_completed_v1';
  static const _keyVerticalMode = 'reader_vertical_mode';
  static const _keyReadingDirection = 'reader_direction_v1';
  static const _keyPageFitMode = 'reader_page_fit_v1';
  static const _keyFreeZoom = 'reader_free_zoom_v1';
  static const _keyTransitionSpeed = 'reader_transition_speed_v1';
  static const _keyShowPageNumber = 'reader_show_page_number_v1';
  static const _keyTapNavigation = 'reader_tap_navigation_v1';
  static const _keyVolumeNavigation = 'reader_volume_navigation_v1';
  static const _keyDoublePage = 'reader_double_page_v1';
  static const _keyAppBrightness = 'app_brightness_v1';
  static const _keyAutoRescanEnabled = 'library_auto_rescan_v1';
  static const _keyDownloadRoot = 'download_root_v1';
  static const _keyDownloadQueue = 'download_queue_v1';
  static const _keyDownloadArchive = 'download_archive_v1';
  static const _keyWelcomeNoticeSeen = 'welcome_notice_seen_v1';

  static const _keyThemeAccent = 'theme_accent_v1';
  static const _keyMangaSourceLinks = 'manga_source_links_v1';
  static const _keyActiveMangaSource = 'active_manga_source_v1';
  static const _keyMangaDexLanguages = 'mangadex_languages_v1';
  static const _keyHitomiLanguage = 'hitomi_language_v1';
  static const _keyProfileDisplayName = 'profile_display_name_v1';
  static const _keyProfileAvatarPath = 'profile_avatar_path_v1';
  static const _keyManageStorageExplained = 'manage_storage_explained_v1';
  static const _keyUiDensity = 'ui_density_v1';

  static Future<List<String>> getLibraryPaths() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getStringList(_keyLibraryPaths) ?? <String>[];
  }

  static Future<void> setLibraryPaths(List<String> paths) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyLibraryPaths, paths);
  }

  static Future<Map<String, ReadingProgress>> getProgressMap() async {
    final store = await LibraryStore.ensureInitialized();
    return store.getProgressMap();
  }

  static Future<void> setProgressMap(
    Map<String, ReadingProgress> progress,
  ) async {
    final store = await LibraryStore.ensureInitialized();
    await store.replaceProgressMap(progress);
  }

  static Future<void> saveProgress(ReadingProgress value) async {
    await (await LibraryStore.ensureInitialized()).upsertProgress(value);
  }

  static Future<void> saveFavorite(FavoriteEntry value) async {
    await (await LibraryStore.ensureInitialized()).setFavorite(value);
  }

  static Future<void> removeFavorite(String key) async {
    await (await LibraryStore.ensureInitialized()).removeFavorite(key);
  }

  static Future<void> setChapterRead(String key, bool read) async {
    await (await LibraryStore.ensureInitialized()).setChapterRead(key, read);
  }

  static Future<dynamic> getStructured(
    String namespace,
    String legacyKey,
  ) async {
    final store = await LibraryStore.ensureInitialized();
    final saved = await store.getRecord('structured', namespace);
    if (saved != null) return saved;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(legacyKey);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    await store.putRecord('structured', namespace, decoded);
    return decoded;
  }

  static Future<void> setStructured(String namespace, Object value) async {
    await (await LibraryStore.ensureInitialized()).putRecord(
      'structured',
      namespace,
      value,
    );
  }

  static Future<bool> getVerticalMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyVerticalMode) ?? true;
  }

  static Future<void> setVerticalMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyVerticalMode, value);
  }

  static Future<ReadingDirection> getReadingDirection() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_keyReadingDirection);
    if (stored != null) {
      return ReadingDirection.values.firstWhere(
        (item) => item.name == stored,
        orElse: () => ReadingDirection.rightToLeft,
      );
    }

    final legacyVertical = prefs.getBool(_keyVerticalMode);
    if (legacyVertical == null) {
      return ReadingDirection.rightToLeft;
    }
    return legacyVertical
        ? ReadingDirection.vertical
        : ReadingDirection.rightToLeft;
  }

  static Future<void> setReadingDirection(ReadingDirection value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyReadingDirection, value.name);
    await prefs.setBool(_keyVerticalMode, value == ReadingDirection.vertical);
  }

  static Future<PageFitMode> getPageFitMode() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_keyPageFitMode);
    if (stored == null) {
      return PageFitMode.fitWidth;
    }
    return PageFitMode.values.firstWhere(
      (item) => item.name == stored,
      orElse: () => PageFitMode.fitWidth,
    );
  }

  static Future<void> setPageFitMode(PageFitMode value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPageFitMode, value.name);
  }

  static Future<bool> getFreeZoom() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyFreeZoom) ?? true;
  }

  static Future<void> setFreeZoom(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyFreeZoom, value);
  }

  static Future<PageTransitionSpeed> getTransitionSpeed() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_keyTransitionSpeed);
    if (stored == null) {
      return PageTransitionSpeed.normal;
    }
    return PageTransitionSpeed.values.firstWhere(
      (item) => item.name == stored,
      orElse: () => PageTransitionSpeed.normal,
    );
  }

  static Future<void> setTransitionSpeed(PageTransitionSpeed value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTransitionSpeed, value.name);
  }

  static Future<bool> getShowPageNumber() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowPageNumber) ?? true;
  }

  static Future<void> setShowPageNumber(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowPageNumber, value);
  }

  static Future<bool> getTapNavigation() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyTapNavigation) ?? true;
  }

  static Future<void> setTapNavigation(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyTapNavigation, value);
  }

  static Future<bool> getVolumeNavigation() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyVolumeNavigation) ?? true;
  }

  static Future<void> setVolumeNavigation(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyVolumeNavigation, value);
  }

  static Future<bool> getDoublePage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDoublePage) ?? false;
  }

  static Future<void> setDoublePage(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDoublePage, value);
  }

  static Future<double> getAppBrightness() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyAppBrightness) ?? 1.0;
  }

  static Future<void> setAppBrightness(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyAppBrightness, value);
  }

  static Future<bool> getAutoRescanEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAutoRescanEnabled) ?? false;
  }

  static Future<void> setAutoRescanEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoRescanEnabled, value);
  }

  static Future<String?> getDownloadRoot() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getString(_keyDownloadRoot);
  }

  static Future<void> setDownloadRoot(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null || value.trim().isEmpty) {
      await prefs.remove(_keyDownloadRoot);
      return;
    }
    await prefs.setString(_keyDownloadRoot, value);
  }

  static Future<List<Map<String, dynamic>>> getDownloadQueue() async {
    final store = await LibraryStore.ensureInitialized();
    final namespace = 'downloadqueue';
    if (await store.getRecord('migrations', namespace) != true) {
      final legacy = await getStructured(namespace, _keyDownloadQueue);
      if (legacy is List) {
        await store.replaceRecords(
          namespace,
          legacy
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
        );
      }
      await store.putRecord('migrations', namespace, true);
    }
    final rows = await store.readRecords(namespace);
    rows.sort(
      (a, b) =>
          (a['_position'] as int? ?? 0).compareTo(b['_position'] as int? ?? 0),
    );
    return rows;
  }

  static Future<void> setDownloadQueue(List<Map<String, dynamic>> queue) async {
    final store = await LibraryStore.ensureInitialized();
    await store.transaction(() async {
      await store.replaceRecords('downloadqueue', queue);
      await store.putRecord('migrations', 'downloadqueue', true);
    });
  }

  static Future<List<Map<String, dynamic>>> getDownloadArchive() async {
    final store = await LibraryStore.ensureInitialized();
    final namespace = 'downloadarchive';
    if (await store.getRecord('migrations', namespace) != true) {
      final legacy = await getStructured(namespace, _keyDownloadArchive);
      if (legacy is List) {
        await store.replaceRecords(
          namespace,
          legacy
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
        );
      }
      await store.putRecord('migrations', namespace, true);
    }
    final rows = await store.readRecords(namespace);
    rows.sort(
      (a, b) =>
          (a['_position'] as int? ?? 0).compareTo(b['_position'] as int? ?? 0),
    );
    return rows;
  }

  static Future<void> setDownloadArchive(
    List<Map<String, dynamic>> archive,
  ) async {
    final store = await LibraryStore.ensureInitialized();
    await store.transaction(() async {
      await store.replaceRecords('downloadarchive', archive);
      await store.putRecord('migrations', 'downloadarchive', true);
    });
  }

  static Future<bool> getWelcomeNoticeSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyWelcomeNoticeSeen) ?? false;
  }

  static Future<void> setWelcomeNoticeSeen(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyWelcomeNoticeSeen, value);
  }

  static Future<ReadingStats> getReadingStats() async {
    final raw = await getStructured('readingStats', _keyReadingStats);
    return raw is Map
        ? ReadingStats.fromMap(Map<String, dynamic>.from(raw))
        : const ReadingStats();
  }

  static Future<void> setReadingStats(ReadingStats stats) =>
      setStructured('readingStats', stats.toMap());

  static Future<Map<String, FavoriteEntry>> getFavoritesMap() async {
    final store = await LibraryStore.ensureInitialized();
    return store.getFavoritesMap();
  }

  static Future<void> setFavoritesMap(
    Map<String, FavoriteEntry> favorites,
  ) async {
    final store = await LibraryStore.ensureInitialized();
    await store.replaceFavoritesMap(favorites);
  }

  static Future<List<Map<String, dynamic>>> getCategories() async {
    final store = await LibraryStore.ensureInitialized();
    final namespace = 'categories';
    if (await store.getRecord('migrations', namespace) != true) {
      final legacy = await getStructured(namespace, _keyCategories);
      if (legacy is List) {
        await store.replaceRecords(
          namespace,
          legacy
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
        );
      }
      await store.putRecord('migrations', namespace, true);
    }
    final rows = await store.readRecords(namespace);
    rows.sort(
      (a, b) =>
          (a['_position'] as int? ?? 0).compareTo(b['_position'] as int? ?? 0),
    );
    return rows;
  }

  static Future<void> setCategories(
    List<Map<String, dynamic>> categories,
  ) async {
    final store = await LibraryStore.ensureInitialized();
    await store.transaction(() async {
      await store.replaceRecords('categories', categories);
      await store.putRecord('migrations', 'categories', true);
    });
  }

  static Future<bool> getWifiOnlyDownloads() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyWifiOnlyDownloads) ?? false;
  }

  static Future<void> setWifiOnlyDownloads(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyWifiOnlyDownloads, value);
  }

  /// Hilos concurrentes de descarga de páginas (1–8). Default 4.
  static Future<int> getDownloadThreads() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_keyDownloadThreads) ?? 4;
    return value.clamp(1, 8);
  }

  static Future<void> setDownloadThreads(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDownloadThreads, value.clamp(1, 8));
  }

  /// Límite global de velocidad en KB/s. 0 = ilimitado.
  static Future<int> getDownloadSpeedLimitKbps() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyDownloadSpeedLimitKbps) ?? 0;
  }

  static Future<void> setDownloadSpeedLimitKbps(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDownloadSpeedLimitKbps, value < 0 ? 0 : value);
  }

  static Future<bool> getOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyOnboardingCompleted) ?? false;
  }

  static Future<void> setOnboardingCompleted(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboardingCompleted, value);
  }

  static Future<String> getUiDensity() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUiDensity) ?? 'compact';
  }

  static Future<void> setUiDensity(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUiDensity, value);
  }

  static Future<bool> getManageStorageExplained() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyManageStorageExplained) ?? false;
  }

  static Future<void> setManageStorageExplained(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyManageStorageExplained, value);
  }

  static Future<Set<String>> getReadChapterKeys() async {
    final store = await LibraryStore.ensureInitialized();
    return store.getReadChapterKeys();
  }

  static Future<void> setReadChapterKeys(Set<String> keys) async {
    final store = await LibraryStore.ensureInitialized();
    await store.replaceReadChapterKeys(keys);
  }

  /// Color de acento del tema (ARGB int). Null = violeta por defecto.
  static Future<int?> getThemeAccent() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_keyThemeAccent)) {
      return null;
    }
    return prefs.getInt(_keyThemeAccent);
  }

  static Future<void> setThemeAccent(int? argb) async {
    final prefs = await SharedPreferences.getInstance();
    if (argb == null) {
      await prefs.remove(_keyThemeAccent);
    } else {
      await prefs.setInt(_keyThemeAccent, argb);
    }
  }

  /// Id de la fuente online activa (p. ej. `lectortmo`, `mangadex`).
  static Future<String?> getActiveMangaSourceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyActiveMangaSource);
  }

  static Future<void> setActiveMangaSourceId(String? sourceId) async {
    final prefs = await SharedPreferences.getInstance();
    if (sourceId == null || sourceId.isEmpty) {
      await prefs.remove(_keyActiveMangaSource);
    } else {
      await prefs.setString(_keyActiveMangaSource, sourceId);
    }
  }

  /// Idiomas de capítulos MangaDex (`es`, `es-la`, …).
  static Future<List<String>> getMangaDexLanguages() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyMangaDexLanguages) ?? <String>[];
  }

  static Future<void> setMangaDexLanguages(List<String> codes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyMangaDexLanguages, codes);
  }

  /// Idioma del apartado +18 (`spanish`, `english`, `all`, …).
  static Future<String?> getHitomiLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyHitomiLanguage);
  }

  static Future<void> setHitomiLanguage(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyHitomiLanguage, code);
  }

  /// Nombre de perfil (solo local, no cuenta remota).
  static Future<String?> getProfileDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyProfileDisplayName);
  }

  static Future<void> setProfileDisplayName(String? name) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = name?.trim() ?? '';
    if (cleaned.isEmpty) {
      await prefs.remove(_keyProfileDisplayName);
    } else {
      await prefs.setString(_keyProfileDisplayName, cleaned);
    }
  }

  /// Ruta local de la foto de perfil.
  static Future<String?> getProfileAvatarPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyProfileAvatarPath);
  }

  static Future<void> setProfileAvatarPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = path?.trim() ?? '';
    if (cleaned.isEmpty) {
      await prefs.remove(_keyProfileAvatarPath);
    } else {
      await prefs.setString(_keyProfileAvatarPath, cleaned);
    }
  }

  /// Enlace manga local path -> URL online (TMO) para actualizar capítulos.
  static Future<Map<String, String>> getMangaSourceLinks() async {
    final raw = await getStructured('sourceLinks', _keyMangaSourceLinks);
    return raw is Map
        ? raw.map((k, v) => MapEntry(k.toString(), v.toString()))
        : {};
  }

  static Future<void> setMangaSourceLinks(Map<String, String> links) =>
      setStructured('sourceLinks', links);
  static Future<void> setMangaSourceLink(
    String localPath,
    String onlineUrl,
  ) async {
    final store = await LibraryStore.ensureInitialized();
    await store.transaction(() async {
      final links = await getMangaSourceLinks();
      links[localPath] = onlineUrl;
      await setMangaSourceLinks(links);
    });
  }
}
