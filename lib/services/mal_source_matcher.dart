import 'package:html/parser.dart' show parseFragment;

import '../models/catalog_page.dart';
import '../models/online_manga.dart';
import '../utils/app_failure.dart';
import 'myanimelist_client.dart';
import 'online_catalog_service.dart';
import 'source_http_client.dart';

typedef MalCatalogSearch =
    Future<CatalogPage> Function(
      String sourceId,
      String query,
      int page,
      int pageSize,
    );

/// Busca títulos completos y alias declarados por MAL; no utiliza similitud.
class MalSourceMatcher {
  final MalCatalogSearch search;
  static const maxQueries = 4;
  static const maxPagesPerQuery = 2;
  MalSourceMatcher({MalCatalogSearch? search}) : search = search ?? _search;

  static Future<CatalogPage> _search(
    String id,
    String query,
    int page,
    int size,
  ) => OnlineCatalogService.fetchCatalogPageForSource(
    id,
    search: query,
    page: page,
    postsPerPage: size,
  );

  static String titleKey(String value) {
    var text = value.trim();
    for (var pass = 0; pass < 2 && text.contains('&'); pass++) {
      text =
          parseFragment(
            text.replaceAll('<', '&lt;').replaceAll('>', '&gt;'),
          ).text ??
          text;
    }
    text = text.toLowerCase();
    for (final entry in const {
      'áàäâãåā': 'a',
      'éèëêē': 'e',
      'íìïîī': 'i',
      'óòöôõō': 'o',
      'úùüûū': 'u',
      'ñ': 'n',
      'ç': 'c',
    }.entries) {
      for (final rune in entry.key.runes) {
        text = text.replaceAll(String.fromCharCode(rune), entry.value);
      }
    }
    return text.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
  }

  static List<String> titles(MalManga manga) {
    final unique = <String, String>{};
    for (final name in [manga.title, ...manga.alternativeTitles]) {
      final key = titleKey(name);
      if (key.isNotEmpty) unique.putIfAbsent(key, () => name.trim());
    }
    return unique.values.toList();
  }

  Future<SourceSearchResult> findInSource(
    MalManga manga,
    String sourceId, {
    CancellationToken? cancellation,
  }) async {
    final token = cancellation ?? CancellationToken();
    if (!OnlineCatalogService.searchableSourceIds.contains(sourceId)) {
      return SourceSearchResult(
        sourceId: sourceId,
        error: const AppFailure(
          FailureKind.parsing,
          'Fuente no disponible para Mangas MAL.',
        ),
      );
    }
    final names = titles(manga);
    final exact = names.map(titleKey).toSet();
    return SourceHttpClient.withCancellation(token, () async {
      try {
        for (final query in names.take(maxQueries)) {
          for (var page = 1; page <= maxPagesPerQuery; page++) {
            token.check();
            final result = await search(sourceId, query, page, 24);
            token.check();
            final matches = <String, OnlineMangaSummary>{};
            for (final item in result.items) {
              final key = titleKey(item.originalTitle ?? item.title);
              if (key.isNotEmpty && exact.contains(key)) {
                matches.putIfAbsent(
                  item.url,
                  () => item.copyWith(sourceId: sourceId),
                );
              }
            }
            if (matches.isNotEmpty) {
              return SourceSearchResult(
                sourceId: sourceId,
                items: matches.values.toList(),
              );
            }
            if (!result.hasNext || result.items.isEmpty) break;
          }
        }
        return SourceSearchResult(sourceId: sourceId);
      } catch (error) {
        token.check();
        return SourceSearchResult(sourceId: sourceId, error: error);
      }
    });
  }
}
