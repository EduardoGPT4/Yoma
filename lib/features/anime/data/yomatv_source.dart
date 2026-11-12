import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../../config/yoma_web.dart';
import '../../../services/myanimelist_client.dart';
import '../models/anime_models.dart';

class AnimeSourceFailure implements Exception {
  final String message;
  final int? status;
  const AnimeSourceFailure(this.message, [this.status]);
  @override
  String toString() => message;
}

/// Only the first-party public JSON API is used. No web account is loaded.
class YomaTvSource {
  static final origin = YomaWeb.base;
  final Uri base;
  final HttpClient http;
  final Future<String> Function(List<String>) hostCookie;
  final Map<String, String> _cookies = {};
  Future<void>? _handshake;
  YomaTvSource({
    Uri? base,
    HttpClient? http,
    Future<String> Function(List<String>)? hostCookie,
  }) : base = base ?? origin,
       http = http ?? HttpClient(),
       hostCookie = hostCookie ?? MalPlatform.hostCookie {
    this.http.connectionTimeout = const Duration(seconds: 20);
    this.http.maxConnectionsPerHost = 3;
  }
  Future<Map<String, dynamic>> catalog({
    int page = 1,
    String search = '',
    String category = '',
    String season = '',
    String year = '',
    String genre = '',
    String order = 'recent',
    bool seasonal = false,
  }) async => animeMap(
    (await _get('actions.php', {
      'action': 'catalog',
      'page': '$page',
      'search': search,
      'category': category,
      'season': season,
      'year': year,
      'order': order,
      'scope': seasonal ? 'season' : 'all',
      if (genre.isNotEmpty) 'include_genres': jsonEncode([genre]),
    }))['catalog'],
  );
  Future<Map<String, dynamic>> detail(String slug) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,160}$').hasMatch(slug)) {
      throw const AnimeSourceFailure('Identificador de anime inválido.');
    }
    return animeMap(
      (await _get('actions.php', {'action': 'detail', 'slug': slug}))['detail'],
    );
  }

  Future<Map<String, dynamic>> home() async =>
      animeMap((await _get('actions.php', {'action': 'home'}))['home']);
  Future<Map<String, dynamic>> publicIndex() async =>
      _get('catalog-public.php', {});
  final Map<String, Future<Map<String, dynamic>>> _inFlight = {};
  Future<Map<String, dynamic>> _get(String path, Map<String, String> query) {
    final key = base.resolve(path).replace(queryParameters: query).toString();
    final existing = _inFlight[key];
    if (existing != null) return existing;
    final request = _getOnce(path, query);
    _inFlight[key] = request;
    return request.whenComplete(() {
      if (identical(_inFlight[key], request)) _inFlight.remove(key);
    });
  }

  Future<Map<String, dynamic>> _getOnce(
    String path,
    Map<String, String> query,
  ) async {
    try {
      // Serialize a cold handshake; concurrent public requests then share cookies.
      if (_cookies.isEmpty) {
        final pending = _handshake;
        if (pending != null) {
          await pending;
        } else {
          final warm = _request(
            base
                .resolve('actions.php')
                .replace(queryParameters: {'action': 'state'}),
          ).then((_) {});
          _handshake = warm;
          try {
            await warm;
          } finally {
            _handshake = null;
          }
        }
      }
      return await _request(base.resolve(path).replace(queryParameters: query));
    } on AnimeSourceFailure {
      rethrow;
    } catch (error) {
      throw AnimeSourceFailure(
        'No se pudo conectar con YomaTV. Los datos guardados siguen disponibles. ($error)',
      );
    }
  }

  Future<Map<String, dynamic>> _request(Uri uri) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final req = await http.getUrl(uri).timeout(const Duration(seconds: 20));
      req.followRedirects = false;
      req.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 Yoma native public client',
      );
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (_cookies.isNotEmpty) {
        req.headers.set(
          HttpHeaders.cookieHeader,
          _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
        );
      }
      final response = await req.close().timeout(const Duration(seconds: 30));
      for (final cookie in response.cookies) {
        if (cookie.name == '__test' || cookie.name == 'SEASONAV1_WEB') {
          _cookies[cookie.name] = cookie.value;
        }
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        if (bytes.length + chunk.length > 12 * 1024 * 1024) {
          throw const AnimeSourceFailure(
            'El catálogo supera el tamaño permitido.',
          );
        }
        bytes.addAll(chunk);
      }
      final body = utf8.decode(bytes);
      if (attempt == 0 &&
          body.contains('slowAES.decrypt') &&
          body.contains('__test')) {
        final values = RegExp(
          r'toNumbers\("([a-fA-F0-9]+)"\)',
        ).allMatches(body).map((m) => m[1]!).toList();
        if (values.length != 3 || values.any((v) => v.length != 32)) {
          throw const AnimeSourceFailure(
            'No se pudo completar la conexión del alojamiento.',
          );
        }
        final cookie = await hostCookie(values);
        if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(cookie)) {
          throw const AnimeSourceFailure(
            'La verificación del alojamiento no es válida.',
          );
        }
        _cookies['__test'] = cookie;
        continue;
      }
      if (response.statusCode != 200) {
        throw AnimeSourceFailure(
          'YomaTV respondió con HTTP ${response.statusCode}.',
          response.statusCode,
        );
      }
      final value = jsonDecode(body);
      if (value is! Map) {
        throw const AnimeSourceFailure(
          'La fuente no devolvió un catálogo válido.',
        );
      }
      final result = Map<String, dynamic>.from(value);
      if (result['ok'] == false) {
        throw AnimeSourceFailure(
          '${result['message'] ?? 'La fuente no pudo completar la solicitud.'}',
        );
      }
      return result;
    }
    throw const AnimeSourceFailure(
      'No se pudo verificar la conexión con YomaTV.',
    );
  }

  void close() => http.close(force: true);
}
