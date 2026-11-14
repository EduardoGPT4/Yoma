import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../data/library_store.dart';
import '../models/favorite_entry.dart';
import '../models/reading_progress.dart';
import '../providers/chapter_read_provider.dart';
import 'myanimelist_client.dart';
import 'myanimelist_service.dart';

/// Resultado de una sincronización de YomaShi.
class MangaSyncResult {
  final int sent, received;

  /// Hubo sincronización (cuenta conectada y servidor con el manga).
  final bool ran;
  const MangaSyncResult({this.sent = 0, this.received = 0, this.ran = true});
  static const none = MangaSyncResult(ran: false);
}

/// Sincroniza YomaShi entre los dispositivos de una misma cuenta de
/// MyAnimeList (server/private/yoma-sync.php, tipos v2):
///
/// - `manga`: la biblioteca (favoritos). Quitarlo viaja como borrado.
/// - `manga_progress`: dónde vas en cada manga (capítulo y página).
/// - `manga_read`: capítulos leídos. Desmarcarlo viaja como borrado.
///
/// Solo el manga online: los mangas sin conexión se identifican por rutas de
/// archivos de cada teléfono. Lo leído porque ya estaba en MAL no se sube:
/// cada dispositivo lo recibe de MAL. Gana el cambio más reciente.
class MangaSync {
  final MyAnimeListClient client;
  final Future<LibraryStore> Function() database;
  MangaSync({
    MyAnimeListClient? client,
    Future<LibraryStore> Function()? database,
  }) : client = client ?? MyAnimeListService.shared.client,
       database = database ?? LibraryStore.ensureInitialized;

  static const kinds = {'manga', 'manga_progress', 'manga_read'};
  static const stateNamespace = 'yoma_sync_state';
  static const sentNamespace = 'yoma_sync_sent';
  static const pushMax = 200;

  /// Avisa a favoritos, leídos y progreso de que llegaron cambios.
  static final changes = ValueNotifier<int>(0);

  /// La huella de la URL que identifica cada elemento en el servidor.
  static String key(String url) =>
      sha256.convert(utf8.encode(url)).toString().substring(0, 40);

  static String sentKey(int owner, String kind, String key) =>
      '$owner|$kind|$key';

  /// El servidor aún no tiene el manga (versión anterior): se vuelve a
  /// probar pasado [MyAnimeListClient.recheck].
  DateTime? _unsupportedAt;
  bool get unsupported =>
      _unsupportedAt != null &&
      DateTime.now().difference(_unsupportedAt!) < MyAnimeListClient.recheck;
  Future<MangaSyncResult>? _running;

  Future<MangaSyncResult> sync({bool force = false}) {
    if (force) _unsupportedAt = null;
    final running = _running;
    if (running != null) return running;
    final work = _sync();
    _running = work;
    return work.whenComplete(() => _running = null);
  }

  Future<MangaSyncResult> _sync() async {
    if (unsupported) return MangaSyncResult.none;
    final session = await client.credentials.load();
    final profile = session?['profile'];
    final owner = profile is Map && profile['id'] is int
        ? profile['id'] as int
        : 0;
    if (session?['connected'] != true || owner <= 0) {
      return MangaSyncResult.none;
    }
    try {
      final capabilities = await client.request({
        'action': 'sync_capabilities',
      }, expectedOwner: owner);
      final offered = (capabilities['kinds'] as List? ?? const []).toSet();
      if (!offered.containsAll(kinds)) {
        _unsupportedAt = DateTime.now();
        return MangaSyncResult.none;
      }
      final sent = await _push(owner);
      final received = await _pull(owner);
      if (received > 0) changes.value++;
      return MangaSyncResult(sent: sent, received: received);
    } on MalFailure catch (e) {
      if (e.status == 404) {
        _unsupportedAt = DateTime.now();
        return MangaSyncResult.none;
      }
      rethrow;
    }
  }

  /// Cambios de aquí aún no subidos para la cuenta [owner].
  Future<List<Map<String, dynamic>>> pending(int owner) async {
    final store = await database();
    final sent = {
      for (final row in await store.readRecords(sentNamespace))
        '${row['id']}': _int(row['updatedAt']),
    };
    final changes = <Map<String, dynamic>>[];
    void add(
      String kind,
      String url,
      int updatedAt,
      Map<String, dynamic> payload, {
      bool deleted = false,
    }) {
      final id = key(url);
      if (updatedAt <= 0) return;
      if ((sent[sentKey(owner, kind, id)] ?? 0) >= updatedAt) return;
      changes.add({
        'kind': kind,
        'key': id,
        'updated_at': updatedAt,
        if (deleted) 'deleted': true,
        if (!deleted) 'payload': {...payload, 'url': url},
      });
    }

    for (final progress in (await store.getProgressMap()).values) {
      if (!LibraryStore.syncableUrl(progress.mangaPath) ||
          !LibraryStore.syncableUrl(progress.chapterPath)) {
        continue;
      }
      add('manga_progress', progress.mangaPath, progress.updatedAt, {
        'title': progress.mangaTitle,
        'cover': _online(progress.coverPath),
        'chapter_url': progress.chapterPath,
        'chapter_title': progress.chapterTitle,
        'page': progress.pageIndex,
        'source': progress.sourceId ?? '',
      });
    }
    for (final row in await store.readRecords(LibraryStore.mangaSyncLog)) {
      final kind = '${row['kind']}';
      final url = '${row['url']}';
      if (!kinds.contains(kind) || !LibraryStore.syncableUrl(url)) continue;
      final payload = row['payload'];
      add(
        kind,
        url,
        _int(row['updatedAt']),
        kind == 'manga' && payload is Map
            ? {
                'title': '${payload['title'] ?? ''}',
                'cover': _online('${payload['cover'] ?? ''}'),
              }
            : const {},
        deleted: row['deleted'] == true,
      );
    }
    return changes;
  }

  Future<int> _push(int owner) async {
    final changes = await pending(owner);
    final store = await database();
    for (var start = 0; start < changes.length; start += pushMax) {
      final batch = changes.skip(start).take(pushMax).toList();
      await client.request({
        'action': 'sync_push',
        'changes': batch,
      }, expectedOwner: owner);
      // Subido (o el servidor ya tenía algo más reciente, que llegará al bajar).
      await store.transaction(() async {
        for (final change in batch) {
          final id = sentKey(owner, '${change['kind']}', '${change['key']}');
          await store.putRecord(sentNamespace, id, {
            'id': id,
            'updatedAt': change['updated_at'],
          });
        }
      });
    }
    return changes.length;
  }

  Future<int> _pull(int owner) async {
    final store = await database();
    final stateKey = 'manga:$owner';
    var cursor = _int(
      (await store.getRecord(stateNamespace, stateKey) as Map?)?['cursor'],
    );
    var received = 0;
    for (var page = 0; page < 200; page++) {
      final data = await client.request({
        'action': 'sync_pull',
        'since': cursor,
        'limit': 500,
      }, expectedOwner: owner);
      final changes = [
        for (final change in data['changes'] as List? ?? const [])
          if (change is Map && kinds.contains(change['kind']))
            Map<String, dynamic>.from(change),
      ];
      final known = changes.isEmpty ? null : await MangaLocalUrls.load(store);
      await store.transaction(() async {
        for (final change in changes) {
          if (await apply(store, owner, change, known!)) received++;
        }
        cursor = _int(data['cursor'], cursor);
        await store.putRecord(stateNamespace, stateKey, {
          'id': stateKey,
          'cursor': cursor,
          'syncedAt': DateTime.now().millisecondsSinceEpoch,
        });
      });
      if (data['more'] != true) break;
    }
    return received;
  }

  /// Aplica un cambio de otro dispositivo si es más reciente que lo de aquí.
  /// Devuelve si cambió algo.
  @visibleForTesting
  static Future<bool> apply(
    LibraryStore store,
    int owner,
    Map<String, dynamic> change,
    MangaLocalUrls known,
  ) async {
    final kind = '${change['kind']}';
    final id = '${change['key']}';
    final updatedAt = _int(change['updated_at']);
    final deleted = change['deleted'] == true;
    final payload = change['payload'] is Map
        ? Map<String, dynamic>.from(change['payload'] as Map)
        : <String, dynamic>{};
    // Un borrado llega sin URL: se busca entre lo que hay aquí.
    final url = LibraryStore.syncableUrl('${payload['url'] ?? ''}')
        ? '${payload['url']}'
        : known.byKey[id];
    if (url == null || updatedAt <= 0) return false;
    var changed = false;
    if (kind == 'manga_progress') {
      if (deleted) return false;
      final local = (await store.getProgressMap())[url];
      final chapter = '${payload['chapter_url'] ?? ''}';
      if (!LibraryStore.syncableUrl(chapter)) return false;
      if (local != null && local.updatedAt >= updatedAt) return false;
      await store.upsertProgress(
        ReadingProgress(
          mangaPath: url,
          mangaTitle: '${payload['title'] ?? local?.mangaTitle ?? ''}',
          coverPath: _nullIfEmpty(payload['cover']) ?? local?.coverPath,
          chapterPath: chapter,
          chapterTitle: '${payload['chapter_title'] ?? ''}',
          pageIndex: _int(payload['page']),
          updatedAt: updatedAt,
          sourceId: _nullIfEmpty(payload['source']) ?? local?.sourceId,
        ),
      );
      changed = true;
    } else {
      final logged = await store.getRecord(
        LibraryStore.mangaSyncLog,
        '$kind|$url',
      );
      // Lo de aquí es igual o más reciente: se queda (y se subirá).
      if (logged is Map && _int(logged['updatedAt']) >= updatedAt) {
        return false;
      }
      if (kind == 'manga') {
        final has = known.favorites.contains(url);
        if (deleted && has) {
          await store.removeFavorite(url, sync: false);
          known.favorites.remove(url);
          changed = true;
        } else if (!deleted) {
          await store.setFavorite(
            FavoriteEntry(
              key: url,
              title: '${payload['title'] ?? ''}',
              coverPath: _nullIfEmpty(payload['cover']),
            ),
            sync: false,
          );
          known.favorites.add(url);
          changed = !has;
        }
      } else {
        final read = !deleted;
        if (known.read.contains(url) != read) {
          await store.setChapterRead(url, read, sync: false);
          // Como al marcarlo aquí: desmarcado, MAL no vuelve a marcarlo.
          if (read) {
            await store.deleteRecord(
              ChapterReadProvider.unmarkedNamespace,
              url,
            );
            known.read.add(url);
          } else {
            await store.putRecord(ChapterReadProvider.unmarkedNamespace, url, {
              'at': DateTime.now().millisecondsSinceEpoch,
            });
            known.read.remove(url);
          }
          changed = true;
        }
      }
    }
    // Ya está al día: no se vuelve a subir.
    final sent = sentKey(owner, kind, id);
    await store.putRecord(sentNamespace, sent, {
      'id': sent,
      'updatedAt': updatedAt,
    });
    return changed;
  }

  static int _int(Object? value, [int fallback = 0]) => value is int
      ? value
      : value is num
      ? value.toInt()
      : int.tryParse('$value') ?? fallback;

  static String _online(String? value) =>
      value != null && LibraryStore.syncableUrl(value) ? value : '';

  static String? _nullIfEmpty(Object? value) {
    final text = '${value ?? ''}';
    return text.isEmpty ? null : text;
  }
}

/// Favoritos y leídos de aquí, y sus URL por huella (para los borrados).
class MangaLocalUrls {
  final Set<String> favorites, read;
  final Map<String, String> byKey;
  MangaLocalUrls(this.favorites, this.read)
    : byKey = {
        for (final url in {...favorites, ...read})
          if (LibraryStore.syncableUrl(url)) MangaSync.key(url): url,
      };

  static Future<MangaLocalUrls> load(LibraryStore store) async =>
      MangaLocalUrls(
        (await store.getFavoritesMap()).keys.toSet(),
        await store.getReadChapterKeys(),
      );
}
