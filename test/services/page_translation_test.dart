import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/models/page_translation.dart';
import 'package:yomashi/services/image_repository.dart';
import 'package:yomashi/services/page_translation_renderer.dart';
import 'package:yomashi/services/page_translation_service.dart';
import 'package:yomashi/widgets/online_translation_sheet.dart';
import 'package:yomashi/widgets/translation_attribution.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File original;
  late Uint8List originalBytes;
  late PageTranslationService service;
  var calls = 0;
  Map<Object?, Object?>? sent;
  Future<Object?> Function(MethodCall)? handler;
  const url = 'https://example.org/page.png';

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('translation-test-');
    final image = img.Image(width: 300, height: 200);
    img.fill(image, color: img.ColorRgb8(40, 60, 80));
    originalBytes = img.encodePng(image);
    original = await File(
      '${directory.path}/original.png',
    ).writeAsBytes(originalBytes);
    final images = ImageRepository()
      ..cacheDirectory = Directory('${directory.path}/images');
    images.registerOffline(url, original.path);
    service = PageTranslationService(images: images);
    calls = 0;
    sent = null;
    handler = null;
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
    messenger.setMockMethodCallHandler(PageTranslationService.channel, (
      call,
    ) async {
      if (handler != null) return handler!(call);
      if (call.method == 'cancel') return null;
      calls++;
      sent = (call.arguments as Map).cast<Object?, Object?>();
      return {
        'blocks': [
          {
            'left': 50,
            'top': 40,
            'width': 180,
            'height': 90,
            'original': 'Hello',
            'translated': 'Hola',
          },
        ],
      };
    });
  });

  tearDown(() async {
    await service.dispose();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(PageTranslationService.channel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (await directory.exists()) {
      final root = await Directory.systemTemp.resolveSymbolicLinks();
      final actual = await directory.resolveSymbolicLinks();
      if (!p.isWithin(root, actual) ||
          !p.basename(actual).startsWith('translation-test-')) {
        throw StateError('Unexpected test cleanup directory');
      }
      await directory.delete(recursive: true);
    }
  });

  test(
    'online translation paints a separate image and caches by URL and language pair',
    () async {
      final first = await service.translate(
        url: url,
        sourceLanguage: 'en',
        targetLanguage: 'es',
      );
      expect(calls, 1);
      expect(sent?['source'], 'en');
      expect(sent?['target'], 'es');
      expect(sent?['wifiOnly'], isTrue);
      expect(first.blocks.single.original, 'Hello');
      expect(first.textOnlyBlocks, 0);
      expect(await original.readAsBytes(), originalBytes);
      final output = img.decodePng(await File(first.imagePath).readAsBytes())!;
      expect(output.width, 300);
      expect(output.height, 200);
      expect(
        output.getPixel(0, 0).r,
        40,
      ); // The illustration outside the block is intact.
      expect(output.getPixel(51, 41).r, 255);
      final repeated = await service.translate(
        url: url,
        sourceLanguage: 'en',
        targetLanguage: 'es',
      );
      expect(repeated.imagePath, first.imagePath);
      expect(calls, 1);
      await service.translate(
        url: url,
        sourceLanguage: 'en',
        targetLanguage: 'fr',
        wifiOnly: false,
      );
      expect(calls, 2);
      expect(sent?['wifiOnly'], isFalse);
      await service.dispose();
      expect(await File(first.imagePath).exists(), isFalse);
      expect(await original.exists(), isTrue);
    },
  );

  test(
    'translation forwards the image request headers supplied by its caller',
    () async {
      await service.dispose();
      final images = _RecordingImageRepository(original);
      String? requestedUrl;
      const headers = {'Referer': 'https://example.org/reader/'};
      service = PageTranslationService(
        images: images,
        imageHeaders: (page) {
          requestedUrl = page;
          return headers;
        },
      );
      await service.translate(
        url: url,
        sourceLanguage: 'en',
        targetLanguage: 'es',
      );
      expect(requestedUrl, url);
      expect(images.requestedUrl, url);
      expect(images.requestHeaders, headers);
      expect(await original.readAsBytes(), originalBytes);
    },
  );

  test('local pages and identical languages never invoke OCR', () async {
    await expectLater(
      () => service.translate(
        url: original.path,
        sourceLanguage: 'en',
        targetLanguage: 'es',
      ),
      throwsA(isA<TranslationFailure>()),
    );
    await expectLater(
      () => service.translate(
        url: url,
        sourceLanguage: 'es',
        targetLanguage: 'es',
      ),
      throwsA(isA<TranslationFailure>()),
    );
    expect(calls, 0);
  });

  test('cancelling discards a late result without poisoning a retry', () async {
    final entered = Completer<void>(), response = Completer<Object?>();
    handler = (call) async {
      if (call.method == 'cancel') return null;
      entered.complete();
      return response.future;
    };
    final pending = service.translate(
      url: url,
      sourceLanguage: 'en',
      targetLanguage: 'es',
    );
    final expectation = expectLater(
      pending,
      throwsA(isA<TranslationFailure>()),
    );
    await entered.future;
    service.cancel();
    await expectation;
    response.complete({'blocks': []});
    handler = null;
    final retry = await service.translate(
      url: url,
      sourceLanguage: 'en',
      targetLanguage: 'es',
    );
    expect(retry.blocks, hasLength(1));
  });

  test(
    'reader cache evicts old copies without deleting source images',
    () async {
      final images = ImageRepository()
        ..cacheDirectory = Directory('${directory.path}/eviction');
      await service.dispose();
      service = PageTranslationService(images: images);
      PageTranslation? first, last;
      for (var i = 0; i < 9; i++) {
        final page = 'https://example.org/page-$i.png';
        images.registerOffline(page, original.path);
        last = await service.translate(
          url: page,
          sourceLanguage: 'en',
          targetLanguage: 'es',
        );
        first ??= last;
      }
      expect(await File(first!.imagePath).exists(), isFalse);
      expect(await File(last!.imagePath).exists(), isTrue);
      expect(await original.readAsBytes(), originalBytes);
    },
  );

  test(
    'missing text is recoverable and does not overwrite the original',
    () async {
      handler = (_) async => {'blocks': []};
      await expectLater(
        service.translate(url: url, sourceLanguage: 'en', targetLanguage: 'es'),
        throwsA(isA<TranslationFailure>()),
      );
      expect(await original.readAsBytes(), originalBytes);
      handler = null;
      expect(
        (await service.translate(
          url: url,
          sourceLanguage: 'en',
          targetLanguage: 'es',
        )).blocks,
        hasLength(1),
      );
    },
  );

  test(
    'text that cannot fit stays in the transcript and does not erase artwork',
    () async {
      final output = File('${directory.path}/render.png');
      final count = await PageTranslationRenderer.render(original, output, [
        TranslationBlock(
          bounds: const Rect.fromLTWH(50, 40, 10, 10),
          original: 'A',
          translated: List.filled(100, 'mucho texto').join(' '),
        ),
      ]);
      expect(count, 1);
      final image = img.decodePng(await output.readAsBytes())!;
      expect(image.getPixel(51, 41).r, 40);
    },
  );

  test(
    'preparation bounds large images before passing them to native OCR',
    () async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
      // The canvas is intentionally a plain image to keep the fixture small.
      expect(canvas, isA<Canvas>());
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 18000);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final tall = await File(
        '${directory.path}/tall.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      final prepared = File('${directory.path}/prepared.png');
      await PageTranslationRenderer.prepare(tall, prepared);
      final decoded = img.decodePng(await prepared.readAsBytes())!;
      expect(decoded.height, lessThanOrEqualTo(16384));
      expect(decoded.width * decoded.height, lessThanOrEqualTo(8100000));
      image.dispose();
      picture.dispose();
    },
  );

  testWidgets('stored languages match the visible dropdown selections', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'translation_source_v1': 'en',
      'translation_target_v1': 'fr',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: OnlineTranslationSheet(
              service: service,
              pages: const [(number: 1, url: url)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Inglés'), findsOneWidget);
    expect(find.text('Francés'), findsOneWidget);
    expect(find.text('Japonés'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('attribution fits a narrow reader with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: TextButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.image_outlined),
              label: const Wrap(
                children: [TranslationAttribution(), Text('Ver original')],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'translation sheet keeps controls reachable on a small phone and closes safely',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => OnlineTranslationSheet(
                    service: service,
                    pages: const [(number: 3, url: url), (number: 4, url: url)],
                  ),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Traducir página online'), findsOneWidget);
      expect(find.text('Página 3'), findsOneWidget);
      expect(find.text('Descargar modelos solo por Wi-Fi'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Traducir con Google'), 180);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Cerrar traducción'));
      await tester.pumpAndSettle();
      expect(find.text('Traducir página online'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _RecordingImageRepository extends ImageRepository {
  final File image;
  String? requestedUrl;
  Map<String, String>? requestHeaders;

  _RecordingImageRepository(this.image);

  @override
  Future<File> resolve(
    String url, {
    Map<String, String>? headers,
    bool refresh = false,
  }) async {
    requestedUrl = url;
    requestHeaders = headers;
    return image;
  }
}
