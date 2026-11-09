import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/models/catalog_page.dart';
import 'package:yomashi/models/online_manga.dart';
import 'package:yomashi/screens/mal_manga_sources_screen.dart';
import 'package:yomashi/services/mal_source_matcher.dart';
import 'package:yomashi/services/manga_source_adapter.dart';
import 'package:yomashi/services/myanimelist_client.dart';
import 'package:yomashi/services/online_catalog_service.dart';
import '../services/myanimelist_library_test.dart' show LibraryCredentials;
import 'mal_library_screen_test.dart'
    show LibraryFake, malApp, captureMalPreview, loadMalPreviewFonts;

const wanted = MalManga(
  id: 1,
  title: 'Obra principal',
  chaptersRead: 1,
  totalChapters: 10,
  status: 'reading',
  publishingStatus: '',
);

void main() {
  setUpAll(loadMalPreviewFonts);
  late Map<String, MangaSourceAdapter> adapters;
  setUp(() {
    adapters = Map.of(OnlineCatalogService.adapters);
    OnlineCatalogService.adapters.clear();
    for (final id in ['mangadex', 'inmanga']) {
      OnlineCatalogService.adapters[id] = adapters[id]!;
    }
  });
  tearDown(() {
    OnlineCatalogService.adapters
      ..clear()
      ..addAll(adapters);
  });

  testWidgets(
    'shows a successful exact source while another fails and retries it independently',
    (tester) async {
      final client = LibraryFake(LibraryCredentials());
      addTearDown(() => client.http.close(force: true));
      var offline = true;
      final calls = <String>[];
      String? openedSource;
      final matcher = MalSourceMatcher(
        search: (id, query, page, size) async {
          calls.add(id);
          if (id == 'inmanga' && offline) {
            throw const MalFailure('Fuente sin conexión');
          }
          return CatalogPage(
            items: [
              OnlineMangaSummary(
                title: wanted.title,
                url: 'https://$id.example/title',
              ),
            ],
            totalPages: 1,
          );
        },
      );
      await tester.pumpWidget(
        malApp(
          MalMangaSourcesScreen(
            manga: wanted,
            ownerId: 7,
            client: client,
            matcher: matcher,
            onOpen: (manga, source) => openedSource = source,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Coincidencia exacta por título'), findsOneWidget);
      expect(find.text('Reintentar fuente'), findsOneWidget);
      await captureMalPreview(tester, 'source-matches');
      await tester.tap(find.widgetWithText(ListTile, wanted.title));
      expect(openedSource, 'mangadex');
      offline = false;
      await tester.tap(find.text('Reintentar fuente'));
      await tester.pumpAndSettle();
      expect(find.text('Coincidencia exacta por título'), findsNWidgets(2));
      expect(calls.where((id) => id == 'mangadex'), hasLength(1));
    },
  );

  testWidgets(
    'a different or disconnected account cannot start source queries',
    (tester) async {
      final store = LibraryCredentials()..value = null;
      final client = LibraryFake(store);
      addTearDown(() => client.http.close(force: true));
      var calls = 0;
      final matcher = MalSourceMatcher(
        search: (id, query, page, size) async {
          calls++;
          return const CatalogPage(items: [], totalPages: 1);
        },
      );
      await tester.pumpWidget(
        malApp(
          MalMangaSourcesScreen(
            manga: wanted,
            ownerId: 7,
            client: client,
            matcher: matcher,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.textContaining('La cuenta cambió'), findsOneWidget);
    },
  );

  testWidgets(
    'disconnecting cancels pending results and keeps the old manga hidden',
    (tester) async {
      final store = LibraryCredentials();
      final client = LibraryFake(store);
      addTearDown(() => client.http.close(force: true));
      final gate = Completer<CatalogPage>();
      var calls = 0;
      final matcher = MalSourceMatcher(
        search: (id, query, page, size) {
          calls++;
          return gate.future;
        },
      );
      await tester.pumpWidget(
        malApp(
          MalMangaSourcesScreen(
            manga: wanted,
            ownerId: 7,
            client: client,
            matcher: matcher,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      store.value = null;
      client.sessionChanges.value++;
      await tester.pumpAndSettle();
      gate.complete(
        const CatalogPage(
          items: [OnlineMangaSummary(title: 'Obra principal', url: '/late')],
          totalPages: 1,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('La cuenta cambió'), findsOneWidget);
      expect(find.text('Coincidencia exacta por título'), findsNothing);
      expect(calls, 2);
    },
  );
}
