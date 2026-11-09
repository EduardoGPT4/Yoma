import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/main.dart';
import 'package:yomashi/models/catalog_page.dart';
import 'package:yomashi/models/manga_list_filters.dart';
import 'package:yomashi/providers/density_provider.dart';
import 'package:yomashi/utils/title_sanitizer.dart';
import 'package:yomashi/services/online_catalog_service.dart';
import 'package:yomashi/services/manga_source_adapter.dart';
import 'package:yomashi/widgets/app_metrics.dart';
import 'package:yomashi/widgets/app_theme.dart';
import 'package:yomashi/widgets/manga_card.dart';
import 'package:yomashi/widgets/manga_filter_sheet.dart';

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'welcome_notice_seen_v1': true,
      'onboarding_completed_v1': true,
    }),
  );

  test(
    'catalog entities are decoded without losing literal angle brackets',
    () {
      expect(
        TitleSanitizer.clean('Hola, Hola &amp; Hola'),
        'Hola, Hola & Hola',
      );
      expect(TitleSanitizer.clean('&#161;Cap&#237;tulo!'), '¡Capítulo!');
      expect(TitleSanitizer.clean('A &amp;amp; B'), 'A & B');
      expect(TitleSanitizer.clean('<Prince> &lt;3'), '<Prince> <3');
      expect(TitleSanitizer.clean('One Piece | Scan: Equipo'), 'One Piece');
    },
  );

  test('custom accents stay readable on dark surfaces and filled controls', () {
    for (final color in [
      Colors.black,
      Colors.white,
      const Color(0xFFC62828),
      const Color(0xFF7C3AED),
      Colors.yellow,
      Colors.blue,
    ]) {
      final theme = buildYomashiTheme(color, AppMetrics.compact);
      expect(
        contrastRatio(
          theme.colorScheme.primary,
          theme.colorScheme.surfaceContainerHighest,
        ),
        greaterThanOrEqualTo(4.5),
      );
      // Superficie más clara del tema (chips, campos, menús) y su versión
      // seleccionada; antes era el gris #2A2A2A de YomaShi.
      final surface = theme.colorScheme.surfaceContainerHighest;
      for (final background in [
        surface,
        Color.alphaBlend(theme.colorScheme.primary.withAlpha(36), surface),
        theme.colorScheme.surface,
        theme.scaffoldBackgroundColor,
      ]) {
        expect(
          contrastRatio(theme.colorScheme.primary, background),
          greaterThanOrEqualTo(4.5),
        );
      }
      final style = theme.filledButtonTheme.style!;
      expect(
        contrastRatio(
          style.foregroundColor!.resolve({})!,
          style.backgroundColor!.resolve({})!,
        ),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  testWidgets('card exposes categories and a 48-point favorite target', (
    tester,
  ) async {
    var categories = 0;
    var favorites = 0;
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => DensityProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 150,
              height: 280,
              child: MangaCard(
                title: 'Manga de prueba',
                coverPath: null,
                onTap: () {},
                onFavoriteToggle: () => favorites++,
                onLongPress: () => categories++,
              ),
            ),
          ),
        ),
      ),
    );
    final target = find.byTooltip('Añadir a favoritos');
    final size = tester.getSize(target);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    await tester.tap(target);
    expect(favorites, 1);
    await tester.tap(find.byTooltip('Opciones de Manga de prueba'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Categorías'));
    await tester.pumpAndSettle();
    expect(categories, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filters remain usable with large text in a short viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    MangaListFilters? applied;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => MangaFilterSheet.show(
                context: context,
                initialFilters: MangaListFilters.empty,
                isOnline: false,
                onApply: (value) => applied = value,
              ),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Solo favoritos'));
    await tester.scrollUntilVisible(find.text('Aplicar'), 250);
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(applied?.favoritesOnly, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching tabs preserves the search controller and its query', (
    tester,
  ) async {
    final original = Map<String, MangaSourceAdapter>.of(
      OnlineCatalogService.adapters,
    );
    addTearDown(() {
      OnlineCatalogService.adapters
        ..clear()
        ..addAll(original);
    });
    for (final entry in original.entries) {
      OnlineCatalogService.adapters[entry.key] = CallbackSourceAdapter(
        id: entry.key,
        catalogRequest: (_, _, _) async =>
            const CatalogPage(items: [], totalPages: 1),
        feedRequest: () async => [],
        detailRequest: entry.value.detail,
        pagesRequest: entry.value.pages,
      );
    }
    await tester.pumpWidget(const MangaReaderApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Manga'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final field = find.byType(TextField).first;
    final controller = tester.widget<TextField>(field).controller!;
    await tester.enterText(field, 'one piece');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Descargas').last);
    await tester.pump();
    await tester.tap(find.text('Inicio').last);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller,
      same(controller),
    );
    expect(controller.text, 'one piece');
    await tester.tap(find.widgetWithText(TextButton, 'Yoma'));
    await tester.pump();
    await tester.tap(find.text('Anime'));
    await tester.pump();
    await tester.tap(find.text('Ir a Manga'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller,
      same(controller),
    );
    expect(controller.text, 'one piece');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
