import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/features/anime/data/anime_controller.dart';
import 'package:yomashi/features/anime/data/anime_local_store.dart';
import 'package:yomashi/features/anime/data/yomatv_source.dart';
import 'package:yomashi/features/anime/screens/anime_schedule_screen.dart';

import '../unit/native_anime_test.dart' show TestAnimeSource;

/// Catálogo de temporada en dos páginas, como el público de tv.yoma.site.
class _SeasonSource extends TestAnimeSource {
  final requested = <(int, bool)>[];
  bool offline = false;
  @override
  Future<Map<String, dynamic>> catalog({
    int page = 1,
    String search = '',
    String category = '',
    String season = '',
    String year = '',
    String genre = '',
    String order = 'recent',
    bool seasonal = false,
  }) async {
    requested.add((page, seasonal));
    if (offline) throw const AnimeSourceFailure('Sin conexión.');
    Map<String, dynamic> anime(
      String slug,
      int weekday, {
      bool active = true,
    }) => {
      'slug': slug,
      'title': slug.toUpperCase(),
      'weekday': weekday,
      'active': active,
      'latest': '3',
      'cover': '',
    };
    return page == 1
        ? {
            'items': [
              anime('zeta', 3),
              anime('alfa', 3),
              anime('lunes', 1),
              anime('terminado', 3, active: false),
            ],
            'page': 1,
            'pages': 2,
          }
        : {
            'items': [
              anime('domingo', 7),
              anime('alfa', 3),
              anime('sin-dia', 0),
            ],
            'page': 2,
            'pages': 2,
          };
  }
}

void main() {
  late LibraryStore db;
  late _SeasonSource source;
  late AnimeController app;

  Future<void> setUpController(WidgetTester tester) =>
      tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        db = await LibraryStore.initialize(
          database: AppDatabase.forTesting(NativeDatabase.memory()),
        );
        source = _SeasonSource();
        app = AnimeController(
          source: source,
          store: AnimeLocalStore(database: () async => db),
          connectivity: () => const Stream.empty(),
        );
      });

  testWidgets('el horario reúne toda la temporada, por días y sin repetidos', (
    tester,
  ) async {
    await setUpController(tester);
    await tester.runAsync(app.loadSchedule);
    expect(source.requested, [(1, true), (2, true)]);
    expect(app.scheduleFor(3).map((a) => a.slug), ['alfa', 'zeta']);
    expect(app.scheduleFor(1).map((a) => a.slug), ['lunes']);
    expect(app.scheduleFor(7).map((a) => a.slug), ['domingo']);
    // Sin emisión activa o sin día no aparecen.
    expect(app.schedule.map((a) => a.slug), isNot(contains('terminado')));
    expect(app.schedule.map((a) => a.slug), isNot(contains('sin-dia')));

    // Recién cargado no se pide otra vez; sin conexión queda el guardado.
    source.requested.clear();
    await tester.runAsync(app.loadSchedule);
    expect(source.requested, isEmpty);
    final reopened = AnimeController(
      source: source..offline = true,
      store: AnimeLocalStore(database: () async => db),
      connectivity: () => const Stream.empty(),
    );
    await tester.runAsync(() => reopened.loadSchedule(refresh: true));
    expect(reopened.scheduleFor(3), hasLength(2));
    expect(reopened.scheduleError, contains('no se pudo actualizar'));
    reopened.dispose();
    app.dispose();
  });

  test('la próxima emisión se muestra solo si es de esta semana', () {
    final now = DateTime(2026, 11, 12, 10); // jueves
    int at(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;
    expect(
      AnimeScheduleScreen.nextLabel(at(DateTime(2026, 11, 12, 21, 30)), now),
      'Próximo: hoy 21:30 (estimado)',
    );
    expect(
      AnimeScheduleScreen.nextLabel(at(DateTime(2026, 11, 13, 8, 5)), now),
      'Próximo: mañana 08:05 (estimado)',
    );
    expect(
      AnimeScheduleScreen.nextLabel(at(DateTime(2026, 11, 15, 20)), now),
      'Próximo: domingo 20:00 (estimado)',
    );
    expect(
      AnimeScheduleScreen.nextLabel(at(DateTime(2026, 11, 11)), now),
      isNull,
    );
    expect(
      AnimeScheduleScreen.nextLabel(at(DateTime(2026, 12, 1)), now),
      isNull,
    );
    expect(AnimeScheduleScreen.nextLabel(null, now), isNull);
  });

  testWidgets('la pantalla abre en el día de hoy y lleva a la ficha', (
    tester,
  ) async {
    await setUpController(tester);
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AnimeScheduleScreen(
          controller: app,
          detail: opened.add,
          today: DateTime(2026, 11, 11), // miércoles
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Hoy · 2'), findsOneWidget);
    expect(find.text('Lunes · 1'), findsOneWidget);
    expect(find.text('ALFA'), findsOneWidget);
    expect(find.text('ZETA'), findsOneWidget);
    await tester.tap(find.text('ALFA'));
    expect(opened, ['alfa']);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
