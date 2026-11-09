import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/models/chapter.dart';
import 'package:yomashi/models/manga.dart';
import 'package:yomashi/providers/chapter_read_provider.dart';
import 'package:yomashi/providers/library_provider.dart';
import 'package:yomashi/providers/reader_settings_provider.dart';
import 'package:yomashi/screens/reader_screen.dart';
import 'package:yomashi/services/image_repository.dart';
import 'package:yomashi/services/maintenance_service.dart';
import 'package:yomashi/services/manga_source_adapter.dart';
import 'package:yomashi/services/online_catalog_service.dart';
import 'package:yomashi/services/page_translation_service.dart';
import 'package:yomashi/widgets/online_translation_sheet.dart';
import 'package:yomashi/widgets/translation_attribution.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android: real OCR, models, translated page and original restoration', (
    tester,
  ) async {
    final info = await MaintenancePlatform.channel
        .invokeMapMethod<String, dynamic>('info');
    expect(const bool.fromEnvironment('YOMASHI_QA'), isTrue);
    expect(info?['package'], 'app.yomashi.reader.qa');
    await LibraryStore.initialize();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('reader_volume_navigation_v1', false);
    await prefs.setBool('reader_crop_white_v1', false);
    await prefs.setString('translation_source_v1', 'en');
    await prefs.setString('translation_target_v1', 'es');
    await prefs.setBool('translation_wifi_only_v1', false);
    await prefs.setBool('tip_reader-controls_v1', true);
    final root = await Directory(
      '${(await getTemporaryDirectory()).path}/qa-translation-${DateTime.now().microsecondsSinceEpoch}',
    ).create();
    final library = LibraryProvider(),
        settings = ReaderSettingsProvider(),
        reads = ChapterReadProvider();
    await settings.load();
    final service = PageTranslationService();
    const urls = [
      'https://inmanga.com/qa-translation/page-0.png',
      'https://inmanga.com/qa-translation/page-1.png',
      'https://inmanga.com/qa-translation/page-2.png',
    ];
    const blankUrl = 'https://inmanga.com/qa-translation/blank.png';
    final source = OnlineCatalogService.adapters['inmanga']!;
    OnlineCatalogService.adapters['inmanga'] = CallbackSourceAdapter(
      id: 'inmanga',
      catalogRequest: (p, n, q) =>
          source.catalog(page: p, pageSize: n, query: q),
      feedRequest: source.feed,
      detailRequest: source.detail,
      pagesRequest: (ref) async {
        debugPrint('TRANSLATION_QA: reader fixture pages requested: $ref');
        if (ref != 'https://inmanga.com/chapter/qa-translation') {
          throw StateError('Unexpected QA chapter: $ref');
        }
        return urls;
      },
    );
    Future<File> fixture(String name, {bool blank = false}) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
      if (!blank) {
        final painter = TextPainter(
          textDirection: TextDirection.ltr,
          text: const TextSpan(
            text: 'Hello world.\n\nThank you.\n\nPlease read this page.',
            style: TextStyle(fontSize: 56, color: Colors.black, height: 1.4),
          ),
        );
        painter.layout(maxWidth: 760);
        painter.paint(canvas, const Offset(70, 120));
        painter.dispose();
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(900, 1400);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        return await File(
          '${root.path}/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
        picture.dispose();
      }
    }

    Widget host(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: library),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: reads),
      ],
      child: MaterialApp(key: ValueKey(child.runtimeType), home: child),
    );
    Future<void> until(bool Function() condition, {int seconds = 20}) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) {
          debugPrint(
            'TRANSLATION_QA: visible text: ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().join(' | ')}',
          );
          final error = tester.takeException();
          if (error != null) debugPrint('TRANSLATION_QA: widget error: $error');
          fail('Timeout waiting for translation UI');
        }
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    try {
      await tester.pumpWidget(
        host(const Scaffold(body: Text('Comprobando OCR y traducción real'))),
      );
      final original = await fixture('original'),
          blank = await fixture('blank', blank: true);
      final originalBytes = await original.readAsBytes();
      for (final url in urls) {
        ImageRepository.shared.registerOffline(url, original.path);
      }
      ImageRepository.shared.registerOffline(blankUrl, blank.path);
      debugPrint(
        'TRANSLATION_QA: starting real English to Spanish translation',
      );
      final translated = await service.translate(
        url: urls[1],
        sourceLanguage: 'en',
        targetLanguage: 'es',
        wifiOnly: false,
      );
      expect(translated.blocks, isNotEmpty);
      expect(
        translated.blocks.any(
          (b) => b.original.toLowerCase().contains('hello'),
        ),
        isTrue,
      );
      expect(
        translated.blocks.any(
          (b) => b.translated.trim().isNotEmpty && b.translated != b.original,
        ),
        isTrue,
      );
      expect(await File(translated.imagePath).exists(), isTrue);
      expect(await original.readAsBytes(), originalBytes);
      expect(
        (await service.translate(
          url: urls[1],
          sourceLanguage: 'en',
          targetLanguage: 'es',
        )).imagePath,
        translated.imagePath,
      );
      debugPrint(
        'TRANSLATION_QA: real OCR and translation passed (${translated.blocks.length} blocks)',
      );
      await expectLater(
        service.translate(
          url: blankUrl,
          sourceLanguage: 'en',
          targetLanguage: 'es',
          wifiOnly: false,
        ),
        throwsA(isA<TranslationFailure>()),
      );
      final manga = Manga(
        title: 'QA translation',
        path: 'https://inmanga.com/manga/qa-translation',
        chapters: [
          Chapter(
            title: 'Capítulo 1',
            path: 'https://inmanga.com/chapter/qa-translation',
            pages: urls,
          ),
        ],
      );
      expect(
        await OnlineCatalogService.fetchChapterPages(
          'https://inmanga.com/chapter/qa-translation',
        ),
        urls,
      );
      await tester.pumpWidget(
        host(
          ReaderScreen(
            manga: manga,
            initialChapterIndex: 0,
            initialPageIndex: 1,
          ),
        ),
      );
      await until(() => find.text('2/3').evaluate().isNotEmpty);
      await tester.tap(find.byTooltip('Más opciones de lectura'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Traducir página'));
      await tester.pumpAndSettle();
      expect(find.text('Inglés'), findsOneWidget);
      expect(find.text('Español'), findsOneWidget);
      await tester.ensureVisible(find.text('Traducir con Google'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Traducir con Google'));
      await until(
        () => find.byType(TranslationAttribution).evaluate().isNotEmpty,
        seconds: 45,
      );
      await tester.scrollUntilVisible(
        find.text('Ver en el lector'),
        180,
        scrollable: find
            .descendant(
              of: find.byType(OnlineTranslationSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver en el lector'));
      await tester.pumpAndSettle();
      expect(find.text('2/3'), findsOneWidget);
      expect(find.byType(TranslationAttribution), findsOneWidget);
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page,
        closeTo(1, .01),
      );
      await tester.ensureVisible(find.text('Ver original'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver original'));
      await tester.pumpAndSettle();
      expect(find.text('2/3'), findsOneWidget);
      expect(find.byType(TranslationAttribution), findsNothing);
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page,
        closeTo(1, .01),
      );
      expect(await original.readAsBytes(), originalBytes);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        host(const Scaffold(body: Text('Modelos y limpieza'))),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await service.clearModels();
      binding.reportData = {
        'package': info?['package'],
        'ocr': 'real',
        'source': 'en',
        'target': 'es',
        'recognizedBlocks': translated.blocks.length,
        'translatedBlocks': translated.blocks
            .map((b) => {'original': b.original, 'translated': b.translated})
            .toList(),
        'originalPreserved': true,
        'readerPagePreserved': true,
        'modelsDeleted': true,
      };
    } finally {
      OnlineCatalogService.adapters['inmanga'] = source;
      await tester.pumpWidget(const SizedBox());
      await service.dispose();
      library.dispose();
      settings.dispose();
      reads.dispose();
      if (await root.exists()) {
        final actual = await root.resolveSymbolicLinks();
        final parent = await (await getTemporaryDirectory())
            .resolveSymbolicLinks();
        if (!actual.startsWith(
          '$parent${Platform.pathSeparator}qa-translation-',
        )) {
          throw StateError('Unexpected QA cleanup path');
        }
        await root.delete(recursive: true);
      }
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
