import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yomashi/models/manga_list_filters.dart';
import 'package:yomashi/providers/density_provider.dart';
import 'package:yomashi/services/hitomi_service.dart';
import 'package:yomashi/widgets/hitomi_search_panel.dart';
import 'package:yomashi/widgets/manga_filter_sheet.dart';

void main() {
  test(
    'la dirección de sugerencias separa cada letra y el espacio de nombre',
    () {
      expect(
        HitomiService.suggestionUri('big breasts').toString(),
        'https://tagindex.hitomi.la/global/b/i/g/_/b/r/e/a/s/t/s.json',
      );
      expect(
        HitomiService.suggestionUri('female:big').toString(),
        'https://tagindex.hitomi.la/female/b/i/g.json',
      );
      expect(
        HitomiService.suggestionUri('artist:').toString(),
        'https://tagindex.hitomi.la/artist.json',
      );
      expect(
        HitomiService.suggestionUri('-big breasts').toString(),
        'https://tagindex.hitomi.la/global/b/i/g/_/b/r/e/a/s/t/s.json',
      );
      expect(
        HitomiService.suggestionUri('').toString(),
        'https://tagindex.hitomi.la/global.json',
      );
      expect(
        HitomiService.tagToken('female', 'Big Breasts'),
        'female:big_breasts',
      );
    },
  );

  test(
    'el índice descarta electroencefalografista , esternocleidomastoideo  y los espacios de nombre ajenos',
    () {
      final parsed = HitomiService.parseTagSuggestions('''
[
  ["big breasts",470746,"female"],
  ["electroencefalografista ",198897,"female"],
  ["esternocleidomastoideo ",12,"male"],
  ["electroencefalografista con",3,"tag"],
  ["schoolgirl uniform",171487,"female"],
  ["nakadashi",267824,"female"],
  ["original",1,"series"],
  ["algo",1,"desconocido"]
]
''');
      expect(parsed.map((item) => item.token), [
        'female:big_breasts',
        'female:schoolgirl_uniform',
        'female:nakadashi',
        'series:original',
      ]);
      expect(parsed.first.caption, 'Género: female:big_breasts');
      expect(parsed.first.countLabel, '470.746 galerías');
      expect(
        HitomiService.suggestionAllowed('female', 'electroencefalografista '),
        isFalse,
      );
      expect(
        HitomiService.suggestionAllowed('male', 'esternocleidomastoideo con'),
        isFalse,
      );
      expect(HitomiService.tagIsBlocked('adventure'), isFalse);
      expect(HitomiService.tagIsBlocked('electroencefalografista '), isTrue);
    },
  );

  testWidgets('pulsar una etiqueta deja seguir añadiendo otras', (
    tester,
  ) async {
    final queries = <String>[];
    await tester.pumpWidget(
      _host(
        HitomiSearchPanel(
          showPopular: false,
          suggestions: _fakeSuggestions,
          onQueryChanged: queries.add,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'big breasts');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('Género: female:big_breasts'), findsOneWidget);
    expect(find.textContaining('electroencefalografista '), findsNothing);
    expect(find.text('470.746 galerías'), findsOneWidget);

    await tester.tap(find.text('Género: female:big_breasts'));
    await tester.pump();

    expect(queries, ['female:big_breasts']);
    expect(
      find.widgetWithText(InputChip, 'Género: female:big_breasts'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'dilf');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.tap(find.text('Género: male:dilf'));
    await tester.pump();

    expect(queries.last, 'female:big_breasts male:dilf');

    await tester.enterText(find.byType(TextField), 'spanish');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.tap(find.text('Idioma: language:spanish'));
    await tester.pump();

    expect(queries.last, 'female:big_breasts male:dilf language:spanish');

    await tester.tap(find.byTooltip('Quitar etiqueta').first);
    await tester.pump();
    expect(queries.last, 'male:dilf language:spanish');
  });

  testWidgets('un término bloqueado no se ofrece ni se busca', (tester) async {
    final lookups = <String>[];
    final queries = <String>[];
    await tester.pumpWidget(
      _host(
        HitomiSearchPanel(
          showPopular: false,
          suggestions: (query, {int limit = 8}) async {
            lookups.add(query);
            return [];
          },
          onQueryChanged: queries.add,
        ),
      ),
    );
    for (final draft in [
      'electroencefalografista ',
      'guro',
      'tag:RYONA',
      'female:s_n-u f f',
    ]) {
      await tester.enterText(find.byType(TextField), draft);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(find.text('Esa etiqueta no está disponible.'), findsOneWidget);
      expect(find.textContaining('Buscar título'), findsNothing);
      expect(find.byType(InputChip), findsNothing);
    }
    expect(lookups, isEmpty);
    expect(queries, isEmpty);
  });

  testWidgets('las más buscadas salen al activarlas en los filtros', (
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
                isOnline: true,
                allowType: false,
                allowStatus: false,
                showHitomiTags: true,
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
    expect(find.text('Etiquetas más buscadas'), findsOneWidget);
    await tester.tap(find.text('Etiquetas más buscadas'));
    await tester.scrollUntilVisible(find.text('Aplicar'), 200);
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(applied?.showPopularTags, isTrue);

    await tester.pumpWidget(
      _host(
        HitomiSearchPanel(
          showPopular: true,
          suggestions: _fakeSuggestions,
          onQueryChanged: (_) {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Más buscadas'), findsOneWidget);
    expect(find.text('Artistas'), findsOneWidget);
    expect(find.text('Idioma: language:spanish'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<List<HitomiTagSuggestion>> _fakeSuggestions(
  String query, {
  int limit = 8,
}) async {
  final text = query.toLowerCase();
  if (text.contains('big')) {
    return const [
      HitomiTagSuggestion(
        namespace: 'female',
        name: 'big breasts',
        count: 470746,
      ),
      HitomiTagSuggestion(
        namespace: 'female',
        name: 'electroencefalografista ',
        count: 9,
      ),
      HitomiTagSuggestion(namespace: 'male', name: 'big penis', count: 100),
    ];
  }
  if (text.contains('dilf')) {
    return const [
      HitomiTagSuggestion(namespace: 'male', name: 'dilf', count: 1200),
    ];
  }
  if (text.contains('spanish') || text.isEmpty || text == 'language:') {
    return const [
      HitomiTagSuggestion(namespace: 'language', name: 'spanish', count: 61452),
    ];
  }
  return const [];
}

Widget _host(Widget child) {
  return ChangeNotifierProvider(
    create: (_) => DensityProvider(),
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}
