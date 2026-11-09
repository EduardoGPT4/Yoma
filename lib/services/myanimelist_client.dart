import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MalFailure implements Exception {
  final String message;
  final int status;
  const MalFailure(this.message, [this.status = 0]);
  @override
  String toString() => message;
}

abstract class MalCredentialStore {
  Future<Map<String, dynamic>?> load();
  Future<void> save(Map<String, dynamic> value);
  Future<void> clear();

  /// Memory/fixture fallback. Device storage overrides this with native atomic CAS.
  Future<bool> replaceIfToken(
    String? expectedToken,
    Map<String, dynamic>? value,
  ) async {
    if ((await load())?['device_token'] != expectedToken) return false;
    if (value == null) {
      await clear();
    } else {
      await save(value);
    }
    return true;
  }
}

class MalPlatform extends MalCredentialStore {
  static const channel = MethodChannel('app.yomashi.reader/myanimelist');
  @override
  Future<Map<String, dynamic>?> load() async {
    if (!Platform.isAndroid) return null;
    final value = await channel.invokeMethod<String>('load');
    return value == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(value) as Map);
  }

  @override
  Future<void> save(Map<String, dynamic> value) async {
    if (!Platform.isAndroid) {
      throw const MalFailure('La conexión segura está disponible en Android.');
    }
    await channel.invokeMethod<void>('save', jsonEncode(value));
  }

  @override
  Future<void> clear() async {
    if (Platform.isAndroid) await channel.invokeMethod<void>('clear');
  }

  @override
  Future<bool> replaceIfToken(
    String? expectedToken,
    Map<String, dynamic>? value,
  ) async {
    if (!Platform.isAndroid) return super.replaceIfToken(expectedToken, value);
    return await channel.invokeMethod<bool>('replaceIfToken', {
          'expectedToken': expectedToken,
          'value': value == null ? null : jsonEncode(value),
        }) ??
        false;
  }

  static Future<void> openBrowser(String value) =>
      channel.invokeMethod('openBrowser', value);
  static Future<String> hostCookie(List<String> values) async =>
      (await channel.invokeMethod<String>('hostCookie', {
        'key': values[0],
        'iv': values[1],
        'ciphertext': values[2],
      }))!;
}

class MalManga {
  final int id, chaptersRead, totalChapters;
  final String title, status, publishingStatus;
  final String? picture;
  final List<String> alternativeTitles;
  const MalManga({
    required this.id,
    required this.title,
    required this.chaptersRead,
    required this.totalChapters,
    required this.status,
    required this.publishingStatus,
    this.picture,
    this.alternativeTitles = const [],
  });
  factory MalManga.fromMap(Map<String, dynamic> m) => MalManga(
    id: m['id'] as int,
    title: m['title'] as String,
    chaptersRead: m['chapters_read'] as int,
    totalChapters: m['num_chapters'] as int,
    status: m['status'] as String,
    publishingStatus: m['publishing_status'] as String? ?? '',
    picture: m['picture'] as String?,
    alternativeTitles:
        (m['alternative_titles'] as List?)
            ?.whereType<String>()
            .where((title) => title.trim().isNotEmpty)
            .toList() ??
        const [],
  );
}

class MalMangaPage {
  final List<MalManga> items;
  final int? nextOffset;
  const MalMangaPage({required this.items, this.nextOffset});
}

class MyAnimeListClient {
  /// Signals committed credential changes without exposing the device token.
  final sessionChanges = ValueNotifier<int>(0);
  static final endpoint = Uri.parse(
    'https://hk-br035.gt.tc/seasonav1/yomashi-api.php',
  );
  final Uri api;
  final HttpClient http;
  final MalCredentialStore credentials;
  final Future<String> Function(List<String>) solveHostCookie;
  String? _cookie;
  Future<Map<String, dynamic>?>? _accountRequest;
  MyAnimeListClient({
    Uri? api,
    HttpClient? http,
    MalCredentialStore? credentials,
    Future<String> Function(List<String>)? solveHostCookie,
  }) : api = api ?? endpoint,
       http = http ?? HttpClient(),
       credentials = credentials ?? MalPlatform(),
       solveHostCookie = solveHostCookie ?? MalPlatform.hostCookie {
    this.http.connectionTimeout = const Duration(seconds: 15);
    this.http.maxConnectionsPerHost = 2;
  }
  static int? parseId(String input) {
    final raw = input.trim();
    final direct = int.tryParse(raw);
    if (direct != null) {
      return direct > 0 && direct <= 999999999 ? direct : null;
    }
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'myanimelist.net' ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    final match = RegExp(
      r'^/manga/([1-9][0-9]{0,8})(?:/|$)',
    ).firstMatch(uri.path);
    return match == null ? null : int.parse(match[1]!);
  }

  Future<Map<String, dynamic>> request(
    Map<String, dynamic> input, {
    bool anonymous = false,
    int? expectedOwner,
  }) async {
    final auth = anonymous ? null : await credentials.load();
    return _requestWithSession(
      input,
      auth,
      anonymous: anonymous,
      expectedOwner: expectedOwner,
    );
  }

  Future<Map<String, dynamic>> _requestWithSession(
    Map<String, dynamic> input,
    Map<String, dynamic>? auth, {
    bool anonymous = false,
    int? expectedOwner,
  }) async {
    if (!anonymous && auth == null) {
      throw const MalFailure('Conecta tu cuenta de MyAnimeList.', 401);
    }
    if (expectedOwner != null &&
        (auth?['profile'] as Map?)?['id'] != expectedOwner) {
      throw const MalFailure(
        'La cuenta cambió. Vuelve a seleccionar el manga.',
        409,
      );
    }
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        if (!anonymous &&
            (await credentials.load())?['device_token'] !=
                auth!['device_token']) {
          throw const MalFailure(
            'La conexión cambió. Actualízala antes de continuar.',
            409,
          );
        }
        final req = await http.postUrl(api);
        req.followRedirects = false;
        // The host may answer its cookie challenge before reading a chunked
        // request. Send a fixed-size body and avoid reusing that connection.
        req.persistentConnection = false;
        req.headers.contentType = ContentType.json;
        if (auth != null) {
          req.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer ${auth['device_token']}',
          );
          // The shared hosting proxy strips Authorization before PHP.
          req.headers.set('X-YomaShi-Token', auth['device_token']);
        }
        if (_cookie != null) {
          req.headers.set(HttpHeaders.cookieHeader, '__test=$_cookie');
        }
        final body = utf8.encode(
          jsonEncode({...input, 'owner_id': ?expectedOwner}),
        );
        req.contentLength = body.length;
        req.add(body);
        final response = await req.close().timeout(const Duration(seconds: 70));
        final bytes = <int>[];
        await for (final chunk in response.timeout(
          const Duration(seconds: 15),
        )) {
          if (bytes.length + chunk.length > 512 * 1024) {
            throw const MalFailure(
              'Respuesta de MyAnimeList demasiado grande.',
            );
          }
          bytes.addAll(chunk);
        }
        final text = utf8.decode(bytes);
        if (attempt == 0 &&
            text.contains('slowAES.decrypt') &&
            text.contains('__test')) {
          final values = RegExp(
            'toNumbers\\("([a-fA-F0-9]+)"\\)',
          ).allMatches(text).map((m) => m[1]!).toList();
          if (values.length != 3 || values.any((v) => v.length != 32)) {
            throw const MalFailure('No se pudo verificar el alojamiento.');
          }
          _cookie = await solveHostCookie(values);
          if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(_cookie!)) {
            throw const MalFailure('No se pudo verificar el alojamiento.');
          }
          continue;
        }
        final data = jsonDecode(text);
        if (data is! Map) {
          throw const MalFailure('Respuesta inválida del servidor.');
        }
        if (!anonymous &&
            (await credentials.load())?['device_token'] !=
                auth!['device_token']) {
          throw const MalFailure(
            'La conexión cambió. Actualízala antes de continuar.',
            409,
          );
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          if (response.statusCode == 401 && !anonymous) {
            if (await credentials.replaceIfToken(
              auth!['device_token'] as String?,
              null,
            )) {
              sessionChanges.value++;
            }
          }
          throw MalFailure(
            data['error'] is String
                ? data['error'] as String
                : 'No se pudo completar la conexión con MyAnimeList.',
            response.statusCode,
          );
        }
        return Map<String, dynamic>.from(data);
      }
      throw const MalFailure('El alojamiento no permitió la conexión.');
    } on MalFailure {
      rethrow;
    } on TimeoutException {
      throw const MalFailure(
        'MyAnimeList tardó demasiado. El progreso pendiente se conserva.',
      );
    } on SocketException {
      throw const MalFailure(
        'Sin conexión con MyAnimeList. El progreso pendiente se conserva.',
      );
    } on HttpException {
      throw const MalFailure(
        'La conexión se interrumpió. Vuelve a intentarlo.',
      );
    } on FormatException {
      throw const MalFailure(
        'El servidor no devolvió una respuesta válida de MyAnimeList.',
      );
    }
  }

  Future<Map<String, dynamic>> begin() async {
    final originalToken =
        (await credentials.load())?['device_token'] as String?;
    final value = await request({'action': 'start'}, anonymous: true);
    final uri = Uri.tryParse(value['connect_url'] as String? ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'hk-br035.gt.tc' ||
        uri.port != 443 ||
        uri.path != '/seasonav1/yomashi-connect.php' ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        !RegExp(
          r'^[a-f0-9]{32}$',
        ).hasMatch(value['device_id'] as String? ?? '') ||
        uri.queryParameters['device'] != value['device_id'] ||
        !RegExp(
          r'^[a-f0-9]{64}$',
        ).hasMatch(value['device_token'] as String? ?? '')) {
      throw const MalFailure('El servidor devolvió una conexión inválida.');
    }
    if (!await credentials.replaceIfToken(originalToken, value)) {
      throw const MalFailure(
        'La conexión cambió. Actualízala antes de continuar.',
        409,
      );
    }
    sessionChanges.value++;
    return value;
  }

  Future<Map<String, dynamic>?> account() {
    return _accountRequest ??= _loadAccount().whenComplete(
      () => _accountRequest = null,
    );
  }

  Future<Map<String, dynamic>?> _loadAccount() async {
    final auth = await credentials.load();
    if (auth == null) return null;
    final status = await _requestWithSession({'action': 'status'}, auth);
    final profile = status['profile'];
    final previous = auth['profile'];
    // Older backend versions omit picture. Preserve it only for the same owner;
    // an explicit empty picture from the current API removes the old photo.
    final nextProfile =
        profile is Map &&
            previous is Map &&
            profile['id'] == previous['id'] &&
            !profile.containsKey('picture') &&
            previous.containsKey('picture')
        ? {...profile, 'picture': previous['picture']}
        : profile;
    final next = {
      ...auth,
      'profile': nextProfile,
      'connected': status['connected'] == true,
    };
    if (!await credentials.replaceIfToken(
      auth['device_token'] as String?,
      next,
    )) {
      throw const MalFailure(
        'La conexión cambió. Actualízala antes de continuar.',
        409,
      );
    }
    sessionChanges.value++;
    return next;
  }

  Future<void> disconnect() async {
    // Revoke remotely before forgetting the credential; allow retry on network error.
    final auth = await credentials.load();
    await _requestWithSession({'action': 'disconnect'}, auth);
    if (await credentials.replaceIfToken(
      auth!['device_token'] as String?,
      null,
    )) {
      sessionChanges.value++;
    }
  }

  Future<List<MalManga>> search(String query) async {
    final id = parseId(query);
    if (id != null) return [await detail(id)];
    if (query.trim().length < 3 || query.trim().length > 64) {
      throw const MalFailure(
        'Escribe entre 3 y 64 caracteres, un ID o una URL de manga MAL.',
      );
    }
    if (query.contains('://')) {
      throw const MalFailure('Usa un enlace de manga de myanimelist.net.');
    }
    final data = await request({'action': 'search', 'query': query.trim()});
    return (data['items'] as List)
        .map((m) => MalManga.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList();
  }

  static const libraryStatuses = ['reading', 'plan_to_read'];

  Future<MalMangaPage> library({
    required String status,
    int offset = 0,
    int limit = 50,
    int? expectedOwner,
  }) async {
    if (!libraryStatuses.contains(status) ||
        offset < 0 ||
        offset > 1000000 ||
        limit < 1 ||
        limit > 100) {
      throw const MalFailure('Filtro o página de la lista MAL inválidos.', 400);
    }
    final auth = await credentials.load();
    final owner = (auth?['profile'] as Map?)?['id'];
    if (auth?['connected'] != true || owner is! int || owner <= 0) {
      throw const MalFailure(
        'Vincula una cuenta de MyAnimeList para ver tus mangas.',
        401,
      );
    }
    final data = await request({
      'action': 'library',
      'status': status,
      'offset': offset,
      'limit': limit,
    }, expectedOwner: expectedOwner ?? owner);
    final rows = data['items'];
    final next = data['next_offset'];
    if (rows is! List ||
        rows.length > limit ||
        (next != null &&
            (next is! int ||
                next <= offset ||
                next > 1000000 ||
                rows.isEmpty))) {
      throw const MalFailure('La lista MAL devolvió una página inválida.', 502);
    }
    try {
      final items = rows
          .map((row) => MalManga.fromMap(Map<String, dynamic>.from(row as Map)))
          .where((manga) => manga.status == status)
          .toList();
      return MalMangaPage(items: items, nextOffset: next as int?);
    } catch (_) {
      throw const MalFailure('La lista MAL contiene datos inválidos.', 502);
    }
  }

  Future<MalManga> detail(int id) async => MalManga.fromMap(
    Map<String, dynamic>.from(
      (await request({'action': 'detail', 'id': id}))['manga'] as Map,
    ),
  );
  Future<MalManga> update(
    int id,
    int chapters,
    String status, {
    bool automatic = false,
    int? expectedOwner,
  }) async {
    if (chapters < 0 ||
        chapters > 100000 ||
        !const {
          'reading',
          'completed',
          'on_hold',
          'dropped',
          'plan_to_read',
        }.contains(status)) {
      throw const MalFailure('Capítulos o estado inválidos.');
    }
    return MalManga.fromMap(
      Map<String, dynamic>.from(
        (await request({
              'action': 'update',
              'id': id,
              'chapters_read': chapters,
              'status': status,
              'automatic': automatic,
            }, expectedOwner: expectedOwner))['manga']
            as Map,
      ),
    );
  }
}
