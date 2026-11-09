import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/providers/density_provider.dart';
import 'package:yomashi/providers/source_provider.dart';
import 'package:yomashi/screens/sources_screen.dart';
import 'package:yomashi/services/mangadex_service.dart';
import 'package:yomashi/widgets/mangadex_language_sheet.dart';

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'active_manga_source_v1': 'mangadex',
    }),
  );

  tearDown(
    () => MangaDexService.setPreferredLanguages(MangaDexLanguage.defaultCodes),
  );

  Future<SourceProvider> openSources(
    WidgetTester tester, {
    double textScale = 1,
  }) async {
    final sources = SourceProvider();
    await sources.load();
    addTearDown(sources.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: sources),
          ChangeNotifierProvider(create: (_) => DensityProvider()),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const SourcesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return sources;
  }

  Future<void> openSelector(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Elegir idiomas'));
    await tester.tap(find.text('Elegir idiomas'));
    await tester.pumpAndSettle();
    expect(find.byType(MangaDexLanguageSheet), findsOneWidget);
  }

  testWidgets(
    'searches languages without accents and keeps the selected chips',
    (tester) async {
      final sources = await openSources(tester);
      await openSelector(tester);
      await tester.enterText(find.byType(TextField), 'INGLES');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(CheckboxListTile, 'Inglés'), findsOneWidget);
      expect(
        find.widgetWithText(CheckboxListTile, 'Español (España)'),
        findsNothing,
      );
      await tester.tap(find.text('Inglés'));
      await tester.pumpAndSettle();
      expect(sources.mangaDexLanguages, ['es', 'es-la', 'en']);
      await tester.tap(find.text('Listo'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilterChip, 'Inglés'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('searches regional codes and handles an empty search result', (
    tester,
  ) async {
    await openSources(tester);
    await openSelector(tester);
    await tester.enterText(find.byType(TextField), 'PT-BR');
    await tester.pumpAndSettle();
    expect(find.text('Portugués (Brasil)'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'not-a-language');
    await tester.pumpAndSettle();
    expect(find.text('No se encontraron idiomas.'), findsOneWidget);
    await tester.tap(find.byTooltip('Borrar búsqueda de idiomas'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(CheckboxListTile, 'Español (España)'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('last selected language stays active and explains the minimum', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'active_manga_source_v1': 'mangadex',
      'mangadex_languages_v1': ['en'],
    });
    final sources = await openSources(tester);
    await openSelector(tester);
    await tester.enterText(find.byType(TextField), 'en');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inglés'));
    await tester.pumpAndSettle();
    expect(find.text('Debe quedar al menos un idioma.'), findsOneWidget);
    expect(sources.mangaDexLanguages, ['en']);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('mangadex-language-en')),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('selector fits a small phone while the keyboard is visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await openSources(tester, textScale: 1.3);
    await openSelector(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.enterText(find.byType(TextField), 'japones');
    await tester.pumpAndSettle();
    expect(find.text('Japonés'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.text('Listo')).bottom, lessThanOrEqualTo(360));
  });

  testWidgets('language control only appears for MangaDex', (tester) async {
    SharedPreferences.setMockInitialValues({
      'active_manga_source_v1': 'inmanga',
    });
    await openSources(tester);
    expect(find.text('Elegir idiomas'), findsNothing);
  });
}
