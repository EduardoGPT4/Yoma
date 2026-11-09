import 'image_repository.dart';
import '../utils/thumbnail_service.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../utils/permissions.dart';
import 'online_catalog_service.dart';

/// Notificaciones de progreso y fin de descarga (Android/iOS/desktop).
///
/// En Android el icono pequeño debe ser monocromo; la portada del manga se
/// muestra como [AndroidNotificationDetails.largeIcon] (a color).
class DownloadNotificationService {
  static const _channelId = 'yomashi_downloads_v2';
  static const _channelName = 'Descargas';
  static const _channelDesc = 'Progreso de descargas de manga';
  static const _coverIconSize = 256;
  static const _smallIcon = 'ic_notification';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _ready = false;
  static DateTime? _lastProgressAt;
  static String? _lastProgressKey;

  /// Cache en memoria: coverUrl -> ruta local del thumbnail de notificación.
  static final Map<String, String> _coverPathCache = <String, String>{};
  static final Map<String, Future<String?>> _coverPathPending =
      <String, Future<String?>>{};

  static Future<void> init() async {
    if (_ready) {
      return;
    }
    if (!Platform.isAndroid && !Platform.isIOS) return;

    try {
      const androidInit = AndroidInitializationSettings(_smallIcon);
      const iosInit = DarwinInitializationSettings();
      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      );

      await _plugin.initialize(settings: initSettings);

      if (Platform.isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        await android?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.defaultImportance,
            playSound: false,
            enableVibration: false,
            showBadge: true,
          ),
        );
      }

      _ready = true;
    } catch (error, stackTrace) {
      debugPrint(
        'DownloadNotificationService.init failed: $error\n$stackTrace',
      );
      _ready = false;
    }
  }

  /// Inicializa el plugin y pide el permiso cuando la Activity ya está lista.
  static Future<bool> ensureReady({bool requestPermission = false}) async {
    if (!_ready) {
      await init();
    }
    if (!_ready) {
      return false;
    }
    if (!Platform.isAndroid) {
      return true;
    }
    if (requestPermission) {
      return StoragePermissionService.requestNotifications();
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.areNotificationsEnabled() ?? false;
  }

  static int _idFor(String jobId) => jobId.hashCode & 0x7fffffff;

  static Future<void> showProgress({
    required String jobId,
    required String title,
    required int completedChapters,
    required int totalChapters,
    String? chapter,
    String? coverUrl,
  }) async {
    if (!await ensureReady()) {
      debugPrint('Download notifications: permission denied or init failed.');
      return;
    }

    final now = DateTime.now();
    final key = '$jobId|$completedChapters|$totalChapters|${chapter ?? ''}';
    if (_lastProgressKey == key) {
      return;
    }
    if (_lastProgressAt != null &&
        now.difference(_lastProgressAt!) < const Duration(milliseconds: 700) &&
        totalChapters > 0 &&
        completedChapters < totalChapters) {
      return;
    }
    _lastProgressAt = now;
    _lastProgressKey = key;

    final max = totalChapters <= 0 ? 100 : totalChapters;
    final progress = totalChapters <= 0 ? 0 : completedChapters.clamp(0, max);
    final percent = totalChapters <= 0
        ? 0
        : ((completedChapters / totalChapters) * 100).round();
    final capsLabel = totalChapters <= 0
        ? 'Descargando...'
        : 'Caps $completedChapters/$totalChapters';
    final body = chapter == null || chapter.isEmpty
        ? '$capsLabel · $percent%'
        : '$chapter · $capsLabel · $percent%';

    await _showAndroid(
      id: _idFor(jobId),
      title: title,
      body: body,
      ongoing: true,
      autoCancel: false,
      showProgress: true,
      maxProgress: max,
      progress: progress,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      category: AndroidNotificationCategory.progress,
    );

    // La portada no debe retrasar la primera aparición de la notificación.
    unawaited(
      _updateProgressWithCover(
        id: _idFor(jobId),
        title: title,
        body: body,
        max: max,
        progress: progress,
        coverUrl: coverUrl,
      ),
    );
  }

  static Future<void> _updateProgressWithCover({
    required int id,
    required String title,
    required String body,
    required int max,
    required int progress,
    String? coverUrl,
  }) async {
    final largeIcon = await _largeIconForCover(coverUrl);
    if (largeIcon == null) {
      return;
    }
    await _showAndroid(
      id: id,
      title: title,
      body: body,
      ongoing: true,
      autoCancel: false,
      showProgress: true,
      maxProgress: max,
      progress: progress,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      category: AndroidNotificationCategory.progress,
      largeIcon: largeIcon,
    );
  }

  static Future<void> showCompleted({
    required String jobId,
    required String title,
    String? coverUrl,
  }) async {
    if (!await ensureReady()) {
      return;
    }
    _lastProgressKey = null;

    final largeIcon = await _largeIconForCover(coverUrl);
    await _showAndroid(
      id: _idFor(jobId),
      title: 'Descarga completada',
      body: title,
      ongoing: false,
      autoCancel: true,
      showProgress: false,
      importance: Importance.high,
      priority: Priority.high,
      largeIcon: largeIcon,
    );
  }

  static Future<void> showFailed({
    required String jobId,
    required String title,
    String? error,
    String? coverUrl,
  }) async {
    if (!await ensureReady()) {
      return;
    }
    _lastProgressKey = null;

    final largeIcon = await _largeIconForCover(coverUrl);
    await _showAndroid(
      id: _idFor(jobId),
      title: 'Error en descarga',
      body: error == null || error.isEmpty ? title : '$title\n$error',
      ongoing: false,
      autoCancel: true,
      showProgress: false,
      importance: Importance.high,
      priority: Priority.high,
      largeIcon: largeIcon,
    );
  }

  static Future<void> cancel(String jobId) async {
    if (!_ready) {
      return;
    }
    try {
      await _plugin.cancel(id: _idFor(jobId));
    } catch (error) {
      debugPrint('DownloadNotificationService.cancel failed: $error');
    }
  }

  static Future<void> cancelAll() async {
    if (!_ready) {
      return;
    }
    try {
      await _plugin.cancelAll();
    } catch (error) {
      debugPrint('DownloadNotificationService.cancelAll failed: $error');
    }
  }

  static Future<void> _showAndroid({
    required int id,
    required String title,
    required String body,
    required bool ongoing,
    required bool autoCancel,
    required bool showProgress,
    required Importance importance,
    required Priority priority,
    int maxProgress = 0,
    int progress = 0,
    AndroidNotificationCategory? category,
    AndroidBitmap<Object>? largeIcon,
  }) async {
    Future<void> showWith({
      required String icon,
      AndroidBitmap<Object>? bitmap,
    }) {
      final android = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        icon: icon,
        importance: importance,
        priority: priority,
        onlyAlertOnce: true,
        playSound: false,
        enableVibration: false,
        showProgress: showProgress,
        maxProgress: maxProgress,
        progress: progress,
        indeterminate: showProgress && maxProgress <= 0,
        ongoing: ongoing,
        autoCancel: autoCancel,
        category: category,
        largeIcon: bitmap,
        visibility: NotificationVisibility.public,
        channelShowBadge: true,
      );
      return _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: android),
      );
    }

    try {
      await showWith(icon: _smallIcon, bitmap: largeIcon);
    } catch (error, stackTrace) {
      debugPrint(
        'DownloadNotificationService.show failed: $error\n$stackTrace',
      );
      try {
        await showWith(icon: '@mipmap/ic_launcher', bitmap: null);
      } catch (fallbackError) {
        debugPrint(
          'DownloadNotificationService.show fallback failed: $fallbackError',
        );
      }
    }
  }

  static Future<AndroidBitmap<Object>?> _largeIconForCover(
    String? coverUrl,
  ) async {
    if (!Platform.isAndroid) {
      return null;
    }
    final path = await _resolveCoverPath(coverUrl);
    if (path == null || path.isEmpty) {
      return null;
    }
    return FilePathAndroidBitmap(path);
  }

  static Future<String?> _resolveCoverPath(String? coverUrl) async {
    final url = coverUrl?.trim();
    if (url == null || url.isEmpty) {
      return null;
    }

    final cached = _coverPathCache[url];
    if (cached != null) {
      if (await File(cached).exists()) {
        return cached;
      }
      _coverPathCache.remove(url);
    }

    final pending = _coverPathPending[url];
    if (pending != null) {
      return pending;
    }

    final future = _downloadAndCacheCover(url);
    _coverPathPending[url] = future;
    try {
      final path = await future;
      if (path != null) {
        _coverPathCache[url] = path;
      }
      return path;
    } finally {
      _coverPathPending.remove(url);
    }
  }

  static Future<String?> _downloadAndCacheCover(String coverUrl) async {
    try {
      final file = await ImageRepository.shared.resolve(
        coverUrl,
        headers: OnlineCatalogService.imageRequestHeaders(coverUrl),
      );
      return (await ThumbnailService.getThumbnail(
        file.path,
        size: _coverIconSize,
      ))?.path;
    } catch (_) {
      return null;
    }
  }
}
