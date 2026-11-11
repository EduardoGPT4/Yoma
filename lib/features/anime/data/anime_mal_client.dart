import 'dart:async';
import '../../../data/library_store.dart';
import '../../../services/myanimelist_client.dart';
import '../../../services/myanimelist_service.dart';
import '../models/anime_models.dart';

class MalAnimeEntry {
  final int id, watched, total;

  /// Año de estreno en MAL; 0 si se desconoce.
  final int year;
  final String title, picture, status;
  MalAnimeEntry.fromJson(Map<String, dynamic> v)
    : id = animeInt(v['id']),
      watched = animeInt(v['episodes_watched']),
      total = animeInt(v['num_episodes']),
      year = animeInt(v['year']),
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
    'year': year,
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

  /// El servidor admite bajar el progreso como deshacer explícito.
  bool _canDecrease = false;

  /// Aviso de la última sincronización que no es un error (por ejemplo, un
  /// deshacer que MAL ya no admite). Se entrega una sola vez.
  String? _notice;
  String? takeNotice() {
    final value = _notice;
    _notice = null;
    return value;
  }

  Future<bool> available() async {
    final auth = await client.credentials.load();
    if (auth?['connected'] != true) return false;
    final token = '${auth?['device_token']}';
    if (_capableToken == token) return true;
    try {
      final features = await client.request({'action': 'anime_capabilities'});
      final capable = features['anime'] == true;
      if (capable) {
        _capableToken = token;
        _canDecrease = features['decrease'] == true;
      }
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
      // Lo que MAL tenía por su cuenta: un deshacer nunca baja de aquí.
      'floor': value.watched,
      'status': value.status,
      'version': DateTime.now().microsecondsSinceEpoch,
    });
  }

  /// Número por debajo del cual un deshacer no baja: lo que MAL tenía antes
  /// de que Yoma enviara nada. Una vinculación anterior a este dato no
  /// permite deshacer lo ya enviado.
  static int _floor(Map<String, dynamic> link) => link.containsKey('floor')
      ? animeInt(link['floor'])
      : animeInt(link['remoteEpisodes']);

  /// Vinculación con el número que MAL tiene ahora. Si no coincide con lo
  /// último que Yoma conocía, MAL cambió por su cuenta y ese es el nuevo
  /// mínimo para deshacer.
  static Map<String, dynamic> _observed(Map<String, dynamic> link, int count) =>
      {
        ...link,
        'remoteEpisodes': count,
        if (count != animeInt(link['remoteEpisodes'])) 'floor': count,
      };

  /// La lista de MAL dice que [slug] va por [count]: se anota en la
  /// vinculación para que el próximo envío espere ese número. Solo sube;
  /// si hay un envío pendiente, manda lo del teléfono y no se toca.
  Future<void> observeRemote(String slug, int count) async {
    final auth = await client.credentials.load();
    final owner = animeInt(animeMap(auth?['profile'])['id']);
    if (auth?['connected'] != true || owner <= 0) return;
    final store = await database();
    await store.transaction(() async {
      final link = animeMap(await store.getRecord('anime_mal_links', slug));
      if (link['owner'] != owner) return;
      if (count <= animeInt(link['remoteEpisodes'])) return;
      final pending = animeMap(
        await store.getRecord('anime_mal_pending', slug),
      );
      if (pending['owner'] == owner && pending['version'] == link['version']) {
        return;
      }
      await store.putRecord('anime_mal_links', slug, _observed(link, count));
    });
  }

  /// Hay un envío a MAL pendiente para [slug] con la cuenta actual.
  Future<bool> hasPending(String slug) async {
    final current = await owner();
    if (current <= 0) return false;
    final store = await database();
    final link = animeMap(await store.getRecord('anime_mal_links', slug));
    final row = animeMap(await store.getRecord('anime_mal_pending', slug));
    return row['owner'] == current &&
        link['owner'] == current &&
        row['version'] == link['version'];
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
      final current =
          old['owner'] == owner && old['version'] == link['version'];
      final base = animeInt(link['remoteEpisodes']);
      if (current && old['decrease'] == true) {
        // Había un deshacer pendiente y se vuelve a marcar un episodio.
        if (episode <= animeInt(old['episodes'])) return;
        if (episode < base) {
          await store.putRecord('anime_mal_pending', slug, {
            ...old,
            'episodes': episode,
          });
          return;
        }
        // De vuelta donde MAL ya está (o más allá): no hay nada que bajar.
        await store.deleteRecord('anime_mal_pending', slug);
      }
      if (episode <= base) return;
      final previous = current && old['decrease'] != true
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

  /// Al desmarcar un episodio, MAL debe quedar en [highest], el episodio
  /// visto más alto que queda en el teléfono.
  ///
  /// Si el avance aún no se envió, basta con bajar o quitar el pendiente. Si
  /// Yoma ya lo envió, se encola un deshacer: baja MAL hasta [highest], pero
  /// nunca por debajo de lo que MAL tenía por su cuenta, y el servidor solo
  /// lo acepta si MAL sigue exactamente donde Yoma lo dejó.
  Future<void> retractWatched(String slug, int highest) async {
    final auth = await client.credentials.load();
    final owner = animeInt(animeMap(auth?['profile'])['id']);
    if (auth?['connected'] != true || owner <= 0) return;
    final store = await database();
    await store.transaction(() async {
      final link = animeMap(await store.getRecord('anime_mal_links', slug));
      if (link['owner'] != owner) return;
      final old = animeMap(await store.getRecord('anime_mal_pending', slug));
      final current =
          old['owner'] == owner && old['version'] == link['version'];
      final remote = animeInt(link['remoteEpisodes']);
      if (current && old['decrease'] != true) {
        if (animeInt(old['episodes']) <= highest) return;
        if (highest > remote) {
          final next = {...old, 'episodes': highest}
            ..remove('conflict')
            ..remove('retryAt');
          await store.putRecord('anime_mal_pending', slug, next);
          return;
        }
        await store.deleteRecord('anime_mal_pending', slug);
      }
      final floor = _floor(link);
      final target = highest > floor ? highest : floor;
      if (target >= remote) {
        if (current && old['decrease'] == true) {
          await store.deleteRecord('anime_mal_pending', slug);
        }
        return;
      }
      await store.putRecord('anime_mal_pending', slug, {
        'owner': owner,
        'malId': link['malId'],
        'version': link['version'],
        'episodes': target,
        'expected_episodes': remote,
        'decrease': true,
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
    final undo = row['decrease'] == true;
    if (!keepRemote && !undo && animeInt(row['episodes']) < count) {
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
      await store.putRecord('anime_mal_links', key, _observed(link, count));
      // Un deshacer sin nada que bajar también termina aquí.
      if (keepRemote || (undo && animeInt(current['episodes']) >= count)) {
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

  /// Retira un pendiente si no cambió desde que se leyó.
  Future<void> _drop(String key, Map<String, dynamic> row) async {
    final store = await database();
    await store.transaction(() async {
      final current = animeMap(await store.getRecord('anime_mal_pending', key));
      if (current['version'] == row['version'] &&
          current['episodes'] == row['episodes'] &&
          current['decrease'] == row['decrease']) {
        await store.deleteRecord('anime_mal_pending', key);
      }
    });
  }

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
      if (row['decrease'] == true) 'decrease': true,
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
    int owner, {
    bool drop = false,
  }) async {
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
      await store.putRecord('anime_mal_links', key, _observed(link, count));
      if (drop || animeInt(current['episodes']) <= count) {
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
      final undo = row['decrease'] == true;
      if (undo && !_canDecrease) {
        // El servidor aún no admite deshacer: MAL conserva su número.
        await _drop(key, row);
        _notice =
            'MyAnimeList conserva el episodio ${row['expected_episodes']} de '
            '«${link['title']}»; este servidor no permite deshacerlo.';
        continue;
      }
      Map<String, dynamic> saved;
      try {
        saved = await _send(row, owner);
      } on MalFailure catch (error) {
        // Un conflicto de un anime no bloquea la sincronización de los demás.
        if (error.status != 409 && error.status != 422) rethrow;
        if (undo) {
          // MAL ya no está donde Yoma lo dejó: no se baja nada y se anota
          // su número actual.
          final seen = error.status == 409
              ? await _autoResolve(key, row, owner, drop: true)
              : null;
          if (seen == null) await _drop(key, row);
          _notice =
              'MyAnimeList cambió desde entonces; no se deshizo el progreso '
              'de «${link['title']}».';
          continue;
        }
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
        final wanted = animeInt(queued['episodes']);
        final done = animeInt(sent['episodes']);
        if (wanted == done) {
          await store.deleteRecord('anime_mal_pending', key);
        } else if (wanted > done) {
          // Se vieron más episodios mientras se enviaba.
          final next = {...queued, 'expected_episodes': done}
            ..remove('decrease');
          await store.putRecord('anime_mal_pending', key, next);
        } else {
          // Se desmarcó mientras se enviaba: lo recién subido se deshace
          // hasta donde corresponde, nunca por debajo de lo que tenía MAL.
          final floor = _floor(currentLink);
          final target = wanted > floor ? wanted : floor;
          if (target >= done) {
            await store.deleteRecord('anime_mal_pending', key);
          } else {
            await store.putRecord('anime_mal_pending', key, {
              ...queued,
              'episodes': target,
              'expected_episodes': done,
              'decrease': true,
            });
          }
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
