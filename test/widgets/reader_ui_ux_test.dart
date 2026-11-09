import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/models/chapter.dart';
import 'package:yomashi/models/manga.dart';
import 'package:yomashi/providers/chapter_read_provider.dart';
import 'package:yomashi/providers/library_provider.dart';
import 'package:yomashi/providers/reader_settings_provider.dart';
import 'package:yomashi/screens/reader_screen.dart';
import 'package:yomashi/widgets/chapter_drawer.dart';
import 'package:yomashi/widgets/reader_settings_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'reader_volume_navigation_v1': false,
    });
  });

  testWidgets(
    'long chapter list opens at current chapter and search selects original index',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final chapters = List.generate(
        1200,
        (index) => Chapter(
          title: 'Capítulo ${(index + 1).toString().padLeft(3, '0')}',
          path: '/manga/chapter-$index',
          pageCount: 22,
        ),
      );
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.4)),
            child: child!,
          ),
          home: Scaffold(
            body: ChapterDrawer(
              chapters: chapters,
              currentIndex: 999,
              onSelect: (value) => selected = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final current = find.text('Capítulo 1000');
      expect(current, findsOneWidget);
      expect(tester.getRect(current).top, greaterThan(200));
      expect(tester.getRect(current).bottom, lessThan(640));
      expect(find.text('Capítulo 001'), findsNothing);

      await tester.enterText(find.byType(TextField), '13');
      await tester.pumpAndSettle();
      expect(find.text('Capítulo 013'), findsOneWidget);
      expect(find.text('1 capítulo'), findsOneWidget);
      await tester.tap(find.text('Capítulo 013'));
      expect(selected, 12);
      await tester.tap(find.text('Ir al actual'));
      await tester.pumpAndSettle();
      expect(current, findsOneWidget);
      expect(tester.getRect(current).bottom, lessThan(640));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reader settings expose image controls at large text and persist changes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = ReaderSettingsProvider();
      await settings.load();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: settings,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.6)),
              child: child!,
            ),
            home: const Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: ReaderSettingsPanel(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final crop = find.widgetWithText(
        SwitchListTile,
        'Recortar márgenes blancos',
      );
      await tester.ensureVisible(crop);
      await tester.tap(crop);
      await tester.pumpAndSettle();
      expect(settings.cropWhite, isTrue);
      expect(
        (await SharedPreferences.getInstance()).getBool('reader_crop_white_v1'),
        isTrue,
      );
      expect(find.text('Imagen'), findsOneWidget);
      expect(find.text('Lectura'), findsOneWidget);
      expect(find.text('Controles'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );

  testWidgets(
    'reader opens settings in place and keeps secondary actions labelled',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final library = LibraryProvider();
      final settings = ReaderSettingsProvider();
      final reads = ChapterReadProvider();
      await settings.load();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: library),
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: reads),
          ],
          child: const MaterialApp(
            home: ReaderScreen(
              manga: Manga(title: 'Fixture', path: '/fixture', chapters: []),
              initialChapterIndex: 0,
              initialPageIndex: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pageCounter = tester.getSize(
        find.widgetWithText(TextButton, '0/0'),
      );
      expect(pageCounter.width, greaterThanOrEqualTo(48));
      expect(pageCounter.height, greaterThanOrEqualTo(48));
      await tester.tap(find.byTooltip('Ajustes del lector'));
      await tester.pumpAndSettle();
      expect(find.text('Ajustes del lector'), findsOneWidget);
      expect(find.byType(ReaderSettingsPanel), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.byTooltip('Cerrar ajustes'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderSettingsPanel), findsNothing);
      await tester.tap(find.byTooltip('Más opciones de lectura'));
      await tester.pumpAndSettle();
      expect(find.text('Usar calidad original'), findsOneWidget);
      expect(find.text('Mis marcadores'), findsOneWidget);
      expect(find.text('Capítulo siguiente'), findsOneWidget);
      expect(find.text('Buscar capítulo en otra fuente'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      library.dispose();
      settings.dispose();
      reads.dispose();
    },
  );
}
