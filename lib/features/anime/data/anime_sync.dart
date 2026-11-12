import 'dart:async';

import '../../../data/library_store.dart';
import '../../../services/myanimelist_client.dart';
import '../../../services/myanimelist_service.dart';
import '../models/anime_models.dart';

/// Resultado de una sincronización.
class AnimeSyncResult {
  final int sent, received;

  /// Hubo sincronización (cuenta conectada y servidor con la función).
  final bool ran;
  const AnimeSyncResult({this.sent = 0, this.received = 0, this.ran = true});
  static const none = AnimeSyncResult(ran: false);
}

/// Sincroniza la biblioteca y el progreso de YomaTV entre los dispositivos y
/// la web de una misma cuenta de MyAnimeList (server/private/yoma-sync.php).
///
/// - Sube lo que cambió aquí desde la última vez (`anime_library` y
///   `anime_progress`); lo que vino de MAL no se sube: cada dispositivo ya lo
///   recibe de MAL.
/// - Baja lo que cambió en otros sitios y lo aplica si es más reciente que lo
///   de aquí (gana el cambio más reciente de cada anime o episodio).
/// - Sin cuenta conectada, o con un servidor que aún no tiene la
///   sincronización, no hace nada.
class AnimeSync {
  final MyAnimeListClient client;
  final Future<LibraryStore> Function() database;
  AnimeSync({
    MyAnimeListClient? client,
    Future<LibraryStore> Function()? database,
  }) : client = client ?? MyAnimeListService.shared.client,
       database = database ?? LibraryStore.ensureInitialized;

  static const stateNamespace = 'yoma_sync_state';
  static const sentNamespace = 'yoma_sync_sent';
  static const pushMax = 200;

  /// El servidor respondió que no tiene la sincronización (versión antigua).
  bool unsupported = false;
  Future<AnimeSyncResult>? _running;

  Future<AnimeSyncResult> sync() {
    final running = _running;
    if (running != null) return running;
    final work = _sync();
    _running = work;
    return work.whenComplete(() => _running = null);
  }

  Future<AnimeSyncResult> _sync() async {
    if (unsupported) return AnimeSyncResult.none;
    final session = await client.credentials.load();
    final owner = animeInt(animeMap(session?['profile'])['id']);
    if (session?['connected'] != true || owner <= 0) {
      return AnimeSyncResult.none;
    }
    try {
      final sent = await _push(owner);
      final received = await _pull(owner);
      return AnimeSyncResult(sent: sent, received: received);
    } on MalFailure catch (e) {
      if (e.status == 404) {
        unsupported = true;
        return AnimeSyncResult.none;
      }
      rethrow;
    }
  }

  static String sentKey(int owner, String kind, String key) =>
      '$owner|$kind|$key';

  /// Cambios de aquí aún no subidos para la cuenta [owner].
  Future<List<Map<String, dynamic>>> pending(int owner) async {
    final store = await database();
    final sent = {
      for (final row in await store.readRecords(sentNamespace))
        '${row['id']}': animeInt(row['updatedAt']),
    };
    final changes = <Map<String, dynamic>>[];
    void add(
      String kind,
      String key,
      int updatedAt,
      Map<String, dynamic> payload,
    ) {
      if (updatedAt <= 0) return;
      if ((sent[sentKey(owner, kind, key)] ?? 0) >= updatedAt) return;
      changes.add({
        'kind': kind,
        'key': key,
        'updated_at': updatedAt,
        'payload': payload,
      });
    }

    for (final row in await store.readRecords('anime_library')) {
      final anime = animeMap(row['anime']);
      add('anime', '${row['slug']}', animeInt(row['updatedAt']), {
        'saved': row['saved'] == true,
        'favorite': row['favorite'] == true,
        'status': '${row['status'] ?? 'planned'}',
        'title': '${anime['title'] ?? ''}',
        'cover': '${anime['cover'] ?? ''}',
      });
    }
    for (final row in await store.readRecords('anime_progress')) {
      if (row['source'] == 'mal') continue;
      final episode = AnimeEpisode.fromJson(animeMap(row['episode']));
      if (episode.slug.isEmpty || episode.number.isEmpty) continue;
      add('episode', episode.key, animeInt(row['updatedAt']), {
        'episode_id': episode.id,
        'position_ms': animeInt(row['positionMs']),
        'duration_ms': animeInt(row['durationMs']),
        'watched': row['watched'] == true,
        'title': '${animeMap(row['anime'])['title'] ?? ''}',
      });
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
    final stateKey = 'anime:$owner';
    var cursor = animeInt(
      animeMap(await store.getRecord(stateNamespace, stateKey))['cursor'],
    );
    var received = 0;
    for (var page = 0; page < 200; page++) {
      final data = await client.request({
        'action': 'sync_pull',
        'since': cursor,
        'limit': 500,
      }, expectedOwner: owner);
      final changes = (data['changes'] as List? ?? []).map(animeMap).toList();
      await store.transaction(() async {
        for (final change in changes) {
          if (await apply(store, owner, change)) received++;
        }
        cursor = animeInt(data['cursor'], cursor);
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

  /// Aplica un cambio de otro dispositivo o de la web si es más reciente que
  /// lo de aquí. Devuelve si cambió algo.
  static Future<bool> apply(
    LibraryStore store,
    int owner,
    Map<String, dynamic> change,
  ) async {
    final kind = '${change['kind']}';
    final key = '${change['key']}';
    final updatedAt = animeInt(change['updated_at']);
    final payload = animeMap(change['payload']);
    final deleted = change['deleted'] == true;
    final namespace = switch (kind) {
      'anime' => 'anime_library',
      'episode' => 'anime_progress',
      _ => null,
    };
    if (namespace == null || updatedAt <= 0) return false;
    final local = animeMap(await store.getRecord(namespace, key));
    // Lo de aquí es igual o más reciente: se queda (y se subirá si no lo está).
    if (local.isNotEmpty && animeInt(local['updatedAt']) >= updatedAt) {
      return false;
    }
    Map<String, dynamic> row;
    if (kind == 'anime') {
      final anime = animeMap(local['anime']).isNotEmpty
          ? animeMap(local['anime'])
          : {
              'slug': key,
              'title': payload['title'] ?? key,
              'cover': payload['cover'] ?? '',
            };
      row = {
        ...local,
        'slug': key,
        'anime': anime,
        'saved': !deleted && payload['saved'] == true,
        'favorite': !deleted && payload['favorite'] == true,
        'status': payload['status'] ?? local['status'] ?? 'planned',
        'score': local['score'] ?? 0,
        'notes': local['notes'] ?? '',
        'updatedAt': updatedAt,
      };
    } else {
      final split = key.lastIndexOf(':');
      if (split <= 0) return false;
      final slug = key.substring(0, split);
      final watched = !deleted && payload['watched'] == true;
      row = {
        ...local,
        'slug': slug,
        'anime': animeMap(local['anime']).isNotEmpty
            ? animeMap(local['anime'])
            : {'slug': slug, 'title': payload['title'] ?? slug},
        'episode': {
          'id': animeInt(
            payload['episode_id'],
            animeInt(animeMap(local['episode'])['id']),
          ),
          'slug': slug,
          'number': key.substring(split + 1),
          'url': animeMap(local['episode'])['url'] ?? '',
        },
        'positionMs': deleted ? 0 : animeInt(payload['position_ms']),
        'durationMs': animeInt(
          payload['duration_ms'],
          animeInt(local['durationMs']),
        ),
        'watched': watched,
        'updatedAt': updatedAt,
      }..remove('source');
      // Desmarcado en otro sitio: MAL no debe volver a marcarlo aquí.
      if (!watched && local['watched'] == true) row['unmarked'] = true;
      if (watched) row.remove('unmarked');
    }
    await store.putRecord(namespace, key, row);
    // Ya está al día: no se vuelve a subir.
    final id = sentKey(owner, kind, key);
    await store.putRecord(sentNamespace, id, {
      'id': id,
      'updatedAt': updatedAt,
    });
    return true;
  }
}
