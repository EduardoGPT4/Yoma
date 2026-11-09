import 'dart:async';
import '../../../data/library_store.dart';
import '../../../services/myanimelist_client.dart';
import '../../../services/myanimelist_service.dart';
import '../models/anime_models.dart';

class MalAnimeEntry {
  final int id, watched, total;
  final String title, picture, status;
  MalAnimeEntry.fromJson(Map<String, dynamic> v)
    : id = animeInt(v['id']),
      watched = animeInt(v['episodes_watched']),
      total = animeInt(v['num_episodes']),
      title = '${v['title']}',
      picture = '${v['picture'] ?? ''}',
      status = '${v['status'] ?? 'plan_to_watch'}';
}

/// Negotiates a new documented backend extension. A missing extension is explicit,
/// not substituted with web credentials or a second OAuth implementation.
class AnimeMalClient {
  final MyAnimeListClient client;
  final Future<LibraryStore> Function() database;
  AnimeMalClient({
    MyAnimeListClient? client,
    Future<LibraryStore> Function()? database,
  }) : client = client ?? MyAnimeListService.shared.client,
       database = database ?? LibraryStore.ensureInitialized;
  Future<void>? _sync;
  Future<bool> available() async {
    final auth = await client.credentials.load();
    if (auth?['connected'] != true) return false;
    try {
      return (await client.request({
            'action': 'anime_capabilities',
          }))['anime'] ==
          true;
    } on MalFailure catch (e) {
      if (e.status == 404) return false;
      rethrow;
    }
  }

  Future<List<MalAnimeEntry>> library({
    String status = 'watching',
    int offset = 0,
  }) async {
    final data = await client.request({
      'action': 'anime_library',
      'status': status,
      'offset': offset,
      'limit': 50,
    });
    return (data['items'] as List? ?? [])
        .map((e) => MalAnimeEntry.fromJson(animeMap(e)))
        .toList();
  }

  Future<MalAnimeEntry> detail(int id) async {
    if (id < 1 || id > 999999999) {
      throw const MalFailure('ID de anime inválido.');
    }
    final auth = await client.credentials.load();
    final owner = animeInt(animeMap(auth?['profile'])['id']);
    final result = await client.request({
      'action': 'anime_detail',
      'id': id,
    }, expectedOwner: owner);
    return MalAnimeEntry.fromJson(animeMap(result['anime']));
  }

  Future<void> link(String slug, MalAnimeEntry value) async {
    final auth = await client.credentials.load();
    final owner = animeInt(animeMap(auth?['profile'])['id']);
    if (auth?['connected'] != true || owner <= 0) {
      throw const MalFailure('Conecta MyAnimeList desde el inicio de Yoma.');
    }
    await (await database()).putRecord('anime_mal_links', slug, {
      'owner': owner,
      'malId': value.id,
      'title': value.title,
      'remoteEpisodes': value.watched,
      'status': value.status,
      'version': DateTime.now().microsecondsSinceEpoch,
    });
  }

  Future<void> queueWatched(String slug, int episode) async {
    if (episode < 1) return;
    final auth = await client.credentials.load();
    final owner = animeInt(animeMap(auth?['profile'])['id']);
    if (auth?['connected'] != true || owner <= 0) return;
    final store = await database();
    await store.transaction(() async {
      final link = animeMap(await store.getRecord('anime_mal_links', slug));
      if (link['owner'] != owner) return;
      final old = animeMap(await store.getRecord('anime_mal_pending', slug));
      final base = animeInt(link['remoteEpisodes']);
      if (episode <= base) return;
      final previous =
          old['owner'] == owner && old['version'] == link['version']
          ? animeInt(old['episodes'])
          : 0;
      await store.putRecord('anime_mal_pending', slug, {
        'owner': owner,
        'malId': link['malId'],
        'version': link['version'],
        'episodes': episode > previous ? episode : previous,
        'expected_episodes': base,
        'status': 'watching',
      });
    });
  }

  Future<List<Map<String, dynamic>>> pending() async {
    final auth = await client.credentials.load();
    final owner = animeInt(animeMap(auth?['profile'])['id']);
    if (auth?['connected'] != true) return [];
    final store = await database();
    final rows = await store.readRecords('anime_mal_pending');
    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      final link = animeMap(
        await store.getRecord('anime_mal_links', '${row['id']}'),
      );
      if (row['owner'] == owner &&
          link['owner'] == owner &&
          row['version'] == link['version']) {
        result.add({...row, 'title': link['title']});
      }
    }
    return result;
  }

  Future<void> resolve(String key, {required bool keepRemote}) async {
    final store = await database();
    final row = animeMap(await store.getRecord('anime_mal_pending', key));
    final auth = await client.credentials.load();
    final owner = animeInt(animeMap(auth?['profile'])['id']);
    if (auth?['connected'] != true || row['owner'] != owner) {
      throw const MalFailure('La cuenta cambió.', 409);
    }
    final data = await client.request({
      'action': 'anime_detail',
      'id': row['malId'],
    }, expectedOwner: owner);
    final remote = animeMap(data['anime']);
    if (remote['id'] != row['malId']) {
      throw const MalFailure('MAL devolvió otro anime.', 502);
    }
    final count = animeInt(remote['episodes_watched']);
    if (!keepRemote && animeInt(row['episodes']) < count) {
      throw const MalFailure(
        'MAL ya tiene más episodios. Conserva su progreso; el historial local no se elimina.',
        409,
      );
    }
    if ((await client.credentials.load())?['device_token'] !=
        auth?['device_token']) {
      throw const MalFailure('La cuenta cambió.', 409);
    }
    await store.transaction(() async {
      final current = animeMap(await store.getRecord('anime_mal_pending', key));
      final link = animeMap(await store.getRecord('anime_mal_links', key));
      if (current['version'] != row['version'] ||
          current['episodes'] != row['episodes'] ||
          link['version'] != row['version'] ||
          link['owner'] != owner) {
        throw const MalFailure(
          'El progreso cambió. Revisa otra vez el pendiente.',
          409,
        );
      }
      await store.putRecord('anime_mal_links', key, {
        ...link,
        'remoteEpisodes': count,
      });
      if (keepRemote) {
        await store.deleteRecord('anime_mal_pending', key);
      } else {
        final next = {...current, 'expected_episodes': count};
        next.remove('conflict');
        next.remove('retryAt');
        await store.putRecord('anime_mal_pending', key, next);
      }
    });
    if (!keepRemote) await flush();
  }

  /// Aparta un pendiente en conflicto; se reintenta más tarde o al resolverlo.
  Future<void> _defer(String key, Map<String, dynamic> row, String why) async {
    final store = await database();
    await store.transaction(() async {
      final current = animeMap(await store.getRecord('anime_mal_pending', key));
      if (current['version'] != row['version']) return;
      final retryAt = DateTime.now().add(conflictRetry);
      await store.putRecord('anime_mal_pending', key, {
        ...current,
        'conflict': why,
        'retryAt': retryAt.millisecondsSinceEpoch,
      });
    });
  }

  static const conflictRetry = Duration(minutes: 15);

  Future<void> flush() {
    final pending = _sync;
    if (pending != null) return pending;
    final request = _flush();
    _sync = request;
    return request.whenComplete(() {
      if (identical(_sync, request)) _sync = null;
    });
  }

  Future<void> _flush() async {
    if (!await available()) return;
    final store = await database();
    final pending = await store.readRecords('anime_mal_pending');
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final row in pending) {
      final auth = await client.credentials.load();
      final owner = animeInt(animeMap(auth?['profile'])['id']);
      if (auth?['connected'] != true) return;
      if (row['owner'] != owner) continue;
      if (animeInt(row['retryAt']) > now) continue;
      final key = '${row['id']}';
      final link = animeMap(await store.getRecord('anime_mal_links', key));
      if (link['version'] != row['version'] || link['owner'] != owner) continue;
      try {
        await client.request({
          'action': 'anime_update',
          'id': row['malId'],
          'episodes_watched': row['episodes'],
          'expected_episodes': row['expected_episodes'],
        }, expectedOwner: owner);
      } on MalFailure catch (error) {
        // Un conflicto de un anime no bloquea la sincronización de los demás.
        if (error.status != 409 && error.status != 422) rethrow;
        await _defer(key, row, error.message);
        continue;
      }
      if ((await client.credentials.load())?['device_token'] !=
          auth?['device_token']) {
        return;
      }
      await store.transaction(() async {
        final currentLink = animeMap(
          await store.getRecord('anime_mal_links', key),
        );
        if (currentLink['owner'] != owner ||
            currentLink['version'] != row['version']) {
          return;
        }
        await store.putRecord('anime_mal_links', key, {
          ...currentLink,
          'remoteEpisodes': row['episodes'],
        });
        final current = animeMap(
          await store.getRecord('anime_mal_pending', key),
        );
        if (current['owner'] != owner || current['version'] != row['version']) {
          return;
        }
        if (animeInt(current['episodes']) <= animeInt(row['episodes'])) {
          await store.deleteRecord('anime_mal_pending', key);
        } else {
          await store.putRecord('anime_mal_pending', key, {
            ...current,
            'expected_episodes': row['episodes'],
          });
        }
      });
    }
  }
}
