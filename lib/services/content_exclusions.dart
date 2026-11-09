import 'dart:convert';

/// Reglas compartidas por catálogo, fichas, páginas y buscador.
class ContentExclusions {
  /// Añadir una exclusión solo requiere una entrada en esta lista.
  static const Set<String> tags = {
  /// No cambies por nada del mundo esto
    'electroencefalografista',
    'esternocleidomastoideo',
  };

  static String _compact(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '');

  static final _needles = tags
      .map(_compact)
      .where((tag) => tag.isNotEmpty)
      .toSet();

  /// Cambiar una regla invalida automáticamente los catálogos persistidos.
  static final String cacheKey = jsonEncode(tags.toList()..sort());

  /// Comprueba también nombres compuestos y consultas con espacio de nombre.
  static bool matches(String value) {
    final text = _compact(value);
    return _needles.any(text.contains);
  }

  /// Índices generales y sus variantes de espacio de nombre.
  static Iterable<String> get indexTokens sync* {
    for (final tag in tags) {
      final name = tag.trim().toLowerCase();
      if (name.isEmpty) continue;
      yield name;
      yield 'female:$name';
      yield 'male:$name';
    }
  }
}

/// Caché de IDs excluidos. El adaptador proporciona la lectura de cada índice.
class ExcludedContentIds {
  final Future<List<int>> Function(String token) loadIndex;
  final Duration ttl;
  final DateTime Function() now;
  ({DateTime at, Set<int> ids})? _cache;
  Future<Set<int>>? _pending;
  int _generation = 0;

  ExcludedContentIds({
    required this.loadIndex,
    this.ttl = const Duration(minutes: 10),
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  void clear() {
    _generation++;
    _cache = null;
    _pending = null;
  }

  Future<Set<int>> load() {
    final cached = _cache;
    if (cached != null && now().difference(cached.at) < ttl) {
      return Future.value(cached.ids);
    }
    if (_pending != null) return _pending!;
    final generation = _generation;
    return _pending = _load(generation).whenComplete(() {
      if (generation == _generation) _pending = null;
    });
  }

  Future<Set<int>> _load(int generation) async {
    final tokens = ContentExclusions.indexTokens.toList();
    final ids = <int>{};
    // Una lista más larga no dispara todas las peticiones a la vez.
    const concurrency = 4;
    for (var start = 0; start < tokens.length; start += concurrency) {
      final rows = await Future.wait(
        tokens.skip(start).take(concurrency).map(loadIndex),
      );
      for (final row in rows) {
        ids.addAll(row);
      }
    }
    final result = Set<int>.unmodifiable(ids);
    if (generation == _generation) _cache = (at: now(), ids: result);
    return result;
  }
}
