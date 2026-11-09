import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/models/catalog_page.dart';
import 'package:yomashi/models/online_manga.dart';
import 'package:yomashi/services/mal_source_matcher.dart';
import 'package:yomashi/services/myanimelist_client.dart';
import 'package:yomashi/services/online_catalog_service.dart';
import 'package:yomashi/utils/app_failure.dart';

const entry = MalManga(
  id: 1,
  title: 'Obra principal',
  chaptersRead: 2,
  totalChapters: 10,
  status: 'reading',
  publishingStatus: '',
  alternativeTitles: ['English Title', '別題'],
);
OnlineMangaSummary item(String title, String url) =>
    OnlineMangaSummary(title: title, url: url);

void main() {
  test('title matching preserves numbers and non-Latin text', () {
    expect(
      MalSourceMatcher.titleKey('  TÍTULO &amp; uno! '),
      MalSourceMatcher.titleKey('Titulo & uno'),
    );
    expect(
      MalSourceMatcher.titleKey('Obra - 2'),
      isNot(MalSourceMatcher.titleKey('Obra')),
    );
    expect(
      MalSourceMatcher.titleKey('同名'),
      isNot(MalSourceMatcher.titleKey('別題')),
    );
    expect(MalSourceMatcher.titleKey('同名'), isNotEmpty);
  });

  test(
    'returns exact full titles without prefixes, sequels or duplicate URLs',
    () async {
      final matcher = MalSourceMatcher(
        search: (id, query, page, size) async => CatalogPage(
          items: [
            item('OBRA PRINCIPAL', '/one'),
            item('Obra principal', '/one'),
            item('Obra principal 2', '/two'),
            item('Obra principal: Extra', '/extra'),
            item('!!!', '/empty'),
          ],
          totalPages: 1,
        ),
      );
      final result = await matcher.findInSource(entry, 'mangadex');
      expect(result.items.map((manga) => manga.url), ['/one']);
      expect(result.items.single.sourceId, 'mangadex');
    },
  );

  test(
    'uses a declared alias after the principal title returns no exact match',
    () async {
      final queries = <String>[];
      final matcher = MalSourceMatcher(
        search: (id, query, page, size) async {
          queries.add(query);
          return CatalogPage(
            items: query == 'English Title'
                ? [item('English Title', '/english')]
                : [],
            totalPages: 1,
          );
        },
      );
      final result = await matcher.findInSource(entry, 'inmanga');
      expect(result.items.single.url, '/english');
      expect(queries, ['Obra principal', 'English Title']);
    },
  );

  test(
    'checks the next result page without changing the active source',
    () async {
      final original = OnlineCatalogService.activeSourceId;
      addTearDown(() => OnlineCatalogService.setActiveSourceId(original));
      OnlineCatalogService.setActiveSourceId('inmanga');
      final pages = <int>[];
      final matcher = MalSourceMatcher(
        search: (id, query, page, size) async {
          pages.add(page);
          return CatalogPage(
            items: [
              item(page == 2 ? 'Obra principal' : 'Obra distinta', '/$page'),
            ],
            currentPage: page,
            totalPages: 2,
          );
        },
      );
      expect(
        (await matcher.findInSource(entry, 'mangadex')).items.single.url,
        '/2',
      );
      expect(pages, [1, 2]);
      expect(OnlineCatalogService.activeSourceId, 'inmanga');
    },
  );

  test(
    'a source failure is reported rather than inventing an approximate match',
    () async {
      final matcher = MalSourceMatcher(
        search: (id, query, page, size) async =>
            throw StateError('fixture offline'),
      );
      final result = await matcher.findInSource(entry, 'mangadex');
      expect(result.error, isA<StateError>());
      expect(result.items, isEmpty);
    },
  );

  test(
    'uses the original source title when display cleanup hides a sequel number',
    () async {
      final summary = OnlineMangaSummary.fromMap(
        const OnlineMangaSummary(
          title: 'Obra principal',
          originalTitle: 'Obra principal - 2',
          url: '/sequel',
        ).toMap(),
      ).copyWith(sourceId: 'mangadex');
      final matcher = MalSourceMatcher(
        search: (id, query, page, size) async =>
            CatalogPage(items: [summary], totalPages: 1),
      );
      expect((await matcher.findInSource(entry, 'mangadex')).items, isEmpty);
      const sequel = MalManga(
        id: 2,
        title: 'Obra principal - 2',
        chaptersRead: 0,
        totalChapters: 0,
        status: 'plan_to_read',
        publishingStatus: '',
      );
      expect(
        (await matcher.findInSource(sequel, 'mangadex')).items.single.url,
        '/sequel',
      );
    },
  );

  test('cancellation stops pagination and alias requests', () async {
    final token = CancellationToken();
    final gate = Completer<CatalogPage>();
    var calls = 0;
    final matcher = MalSourceMatcher(
      search: (id, query, page, size) {
        calls++;
        return gate.future;
      },
    );
    final pending = matcher.findInSource(
      entry,
      'mangadex',
      cancellation: token,
    );
    token.cancel();
    gate.complete(const CatalogPage(items: [], totalPages: 20));
    await expectLater(
      pending,
      throwsA(
        isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.cancelled),
      ),
    );
    expect(calls, 1);
  });

  test('the separate source is never queried from the MAL library', () async {
    var calls = 0;
    final matcher = MalSourceMatcher(
      search: (id, query, page, size) async {
        calls++;
        return const CatalogPage(items: []);
      },
    );
    expect((await matcher.findInSource(entry, 'hitomi')).error, isNotNull);
    expect(calls, 0);
  });
}
