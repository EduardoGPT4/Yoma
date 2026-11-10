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
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'picture': picture,
    'status': status,
    'episodes_watched': watched,
    'num_episodes': total,
  };
}

/// Una página de una lista de anime de MAL. [nextOffset] es `null` en la
/// última; lo decide el servidor, no el número de filas recibidas.
class MalAnimePage {
  final List<MalAnimeEntry> items;
  final int? nextOffset;
  const MalAnimePage(this.items, this.nextOffset);
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

  /// Recibe el número de episodios que MAL tiene confirmado para un anime
  /// cada vez que se envía un avance o se consulta su estado.
  void Function(int malId, int watched, String status)? onRemoteProgress;

  /// Sesión para la que el servidor ya confirmó la extensión de anime; evita
  /// repetir la consulta en cada sincronización.
  String? _capableToken;
  Future<bool> available() async {
    final auth = await client.credentials.load();
    if (auth?['connected'] != true) return false;
    final token = '${auth?['device_token']}';
    if (_capableToken == token) return true;
    try {
      final capable =
          (await client.request({'action': 'anime_capabilities'}))['anime'] ==
          true;
      if (capable) _capableToken = token;
      return capable;
    } on MalFailure catch (e) {
      if (e.status == 404) return false;
      rethrow;
    }
  }

  Future<MalAnimePage> libraryPage({
    String status = 'watching',
    int offset = 0,
  }) async {
    final data = await client.request({
      'action': 'anime_library',
      'status': status,
      'offset': offset,
      'limit': 50,
    });
    final rows = data['items'];
    final next = data['next_offset'];
    // Una respuesta sin lista o con una continuación que no avanza no se
    // toma por una lista vacía: ocultaría animes o repetiría páginas.
    if (rows is! List || (next != null && (next is! int || next <= offset))) {
      throw const MalFailure(
        'MyAnimeList devolvió una lista de anime inválida.',
        502,
      );
    }
    return MalAnimePage(
      rows.map((e) => MalAnimeEntry.fromJson(animeMap(e))).toList(),
      next as int?,
    );
  }

  Future<List<MalAnimeEntry>> library({
    String status = 'watching',
    int offset = 0,
  }) async => (await libraryPage(status: status, offset: offset)).items;

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

  /// Id de la cuenta MAL conectada, o 0 si no hay sesión.
  Future<int> owner() async {
    final auth = await client.credentials.load();
    if (auth?['connected'] != true) return 0;
    return animeInt(animeMap(auth?['profile'])['id']);
  }

  /// Vinculación guardada de un anime de YomaTV para la cuenta actual.
  Future<Map<String, dynamic>?> linkOf(String slug) async {
    final current = await owner();
    if (current <= 0) return null;
    final link = animeMap(
      await (await database()).getRecord('anime_mal_links', slug),
    );
    return link['owner'] == current ? link : null;
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

  /// Al desmarcar un episodio, el pendiente baja a [highest], el episodio
  /// visto más alto que queda en el teléfono. Lo que MAL ya confirmó no se
  /// reduce: Yoma nunca baja el progreso de MAL.
  Future<void> retractWatched(String slug, int highest) async {
    final auth = await client.credentials.load();
    final owner = animeInt(animeMap(auth?['profile'])['id']);
    if (auth?['connected'] != true || owner <= 0) return;
    final store = await database();
    await store.transaction(() async {
      final link = animeMap(await store.getRecord('anime_mal_links', slug));
      final old = animeMap(await store.getRecord('anime_mal_pending', slug));
      if (link['owner'] != owner ||
          old['owner'] != owner ||
          old['version'] != link['version'] ||
          animeInt(old['episodes']) <= highest) {
        return;
      }
      if (highest <= animeInt(link['remoteEpisodes'])) {
        await store.deleteRecord('anime_mal_pending', slug);
        return;
      }
      final next = {...old, 'episodes': highest}
        ..remove('conflict')
        ..remove('retryAt');
      await store.putRecord('anime_mal_pending', slug, next);
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
    // Fuera de la transacción: quien escucha guarda datos por su cuenta.
    onRemoteProgress?.call(
      animeInt(row['malId']),
      count,
      '${remote['status'] ?? ''}',
    );
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

  /// Envía el avance y devuelve el anime tal como quedó en MAL. Una
  /// respuesta que no confirma ese mismo anime con ese mismo número no
  /// cuenta como guardada: el pendiente se conserva y se reintenta.
  Future<Map<String, dynamic>> _send(
    Map<String, dynamic> row,
    int owner,
  ) async {
    final data = await client.request({
      'action': 'anime_update',
      'id': row['malId'],
      'episodes_watched': row['episodes'],
      'expected_episodes': row['expected_episodes'],
    }, expectedOwner: owner);
    final anime = animeMap(data['anime']);
    if (anime['id'] != row['malId'] ||
        animeInt(anime['episodes_watched'], -1) != animeInt(row['episodes'])) {
      throw const MalFailure(
        'MyAnimeList no confirmó el progreso enviado.',
        502,
      );
    }
    return anime;
  }

  /// Resuelve un conflicto con el número actual de MAL, sin bajarlo nunca.
  /// Devuelve `{}` si MAL ya tenía ese avance (el pendiente se elimina), el
  /// pendiente con el número esperado corregido si hay que reenviarlo, o
  /// `null` si necesita revisión (otra obra en MAL o vínculo equivocado).
  Future<Map<String, dynamic>?> _autoResolve(
    String key,
    Map<String, dynamic> row,
    int owner,
  ) async {
    final data = await client.request({
      'action': 'anime_detail',
      'id': row['malId'],
    }, expectedOwner: owner);
    final remote = animeMap(data['anime']);
    if (remote['id'] != row['malId']) return null;
    final count = animeInt(remote['episodes_watched']);
    final total = animeInt(remote['num_episodes']);
    final wanted = animeInt(row['episodes']);
    // Más episodios que los que tiene el anime en MAL: vínculo equivocado.
    if (count < wanted && total > 0 && wanted > total) return null;
    final store = await database();
    Map<String, dynamic>? result;
    await store.transaction(() async {
      final link = animeMap(await store.getRecord('anime_mal_links', key));
      final current = animeMap(await store.getRecord('anime_mal_pending', key));
      if (link['owner'] != owner ||
          link['version'] != row['version'] ||
          current['version'] != row['version']) {
        return;
      }
      await store.putRecord('anime_mal_links', key, {
        ...link,
        'remoteEpisodes': count,
      });
      if (animeInt(current['episodes']) <= count) {
        await store.deleteRecord('anime_mal_pending', key);
        result = {};
        return;
      }
      final next = {...current, 'expected_episodes': count}
        ..remove('conflict')
        ..remove('retryAt');
      await store.putRecord('anime_mal_pending', key, next);
      result = next;
    });
    if (result != null) {
      onRemoteProgress?.call(
        animeInt(row['malId']),
        count,
        '${remote['status'] ?? ''}',
      );
    }
    return result;
  }

  Future<void> _flush() async {
    final session = await client.credentials.load();
    if (session?['connected'] != true) return;
    final account = animeInt(animeMap(session?['profile'])['id']);
    final store = await database();
    final now = DateTime.now().millisecondsSinceEpoch;
    final pending = [
      for (final row in await store.readRecords('anime_mal_pending'))
        if (row['owner'] == account && animeInt(row['retryAt']) <= now) row,
    ];
    // Sin nada que enviar no se consulta al servidor: estar sin conexión no
    // es un error de sincronización si no queda ningún episodio pendiente.
    if (pending.isEmpty) return;
    if (!await available()) return;
    for (final row in pending) {
      final auth = await client.credentials.load();
      final owner = animeInt(animeMap(auth?['profile'])['id']);
      if (auth?['connected'] != true) return;
      if (row['owner'] != owner) continue;
      final key = '${row['id']}';
      final link = animeMap(await store.getRecord('anime_mal_links', key));
      if (link['version'] != row['version'] || link['owner'] != owner) continue;
      // Lo que se envió de verdad: tras resolver un conflicto puede incluir
      // un episodio visto mientras tanto.
      var sent = row;
      Map<String, dynamic> saved;
      try {
        saved = await _send(row, owner);
      } on MalFailure catch (error) {
        // Un conflicto de un anime no bloquea la sincronización de los demás.
        if (error.status != 409 && error.status != 422) rethrow;
        // Lo habitual es que MAL cambiara desde que se guardó el número
        // esperado (web, otra app o una copia de la lista de hace horas): se
        // consulta MAL y se resuelve si es seguro.
        final resolved = error.status == 409
            ? await _autoResolve(key, row, owner)
            : null;
        if (resolved == null) {
          await _defer(key, row, error.message);
          continue;
        }
        // MAL ya tenía ese avance: no hay nada que enviar.
        if (resolved.isEmpty) continue;
        sent = resolved;
        try {
          saved = await _send(resolved, owner);
        } on MalFailure catch (again) {
          if (again.status != 409 && again.status != 422) rethrow;
          await _defer(key, resolved, again.message);
          continue;
        }
      }
      if ((await client.credentials.load())?['device_token'] !=
          auth?['device_token']) {
        return;
      }
      var confirmed = false;
      await store.transaction(() async {
        final currentLink = animeMap(
          await store.getRecord('anime_mal_links', key),
        );
        if (currentLink['owner'] != owner ||
            currentLink['version'] != row['version']) {
          return;
        }
        final status = '${saved['status'] ?? ''}';
        await store.putRecord('anime_mal_links', key, {
          ...currentLink,
          'remoteEpisodes': sent['episodes'],
          if (status.isNotEmpty) 'status': status,
        });
        confirmed = true;
        final queued = animeMap(
          await store.getRecord('anime_mal_pending', key),
        );
        if (queued['owner'] != owner || queued['version'] != row['version']) {
          return;
        }
        if (animeInt(queued['episodes']) <= animeInt(sent['episodes'])) {
          await store.deleteRecord('anime_mal_pending', key);
        } else {
          await store.putRecord('anime_mal_pending', key, {
            ...queued,
            'expected_episodes': sent['episodes'],
          });
        }
      });
      if (confirmed) {
        onRemoteProgress?.call(
          animeInt(sent['malId']),
          animeInt(sent['episodes']),
          '${saved['status'] ?? ''}',
        );
      }
    }
  }
}
