import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/providers/library_provider.dart';
import 'package:yomashi/providers/profile_provider.dart';
import 'package:yomashi/providers/source_provider.dart';
import 'package:yomashi/screens/home_screen.dart';
import 'package:yomashi/screens/mal_library_screen.dart';
import 'package:yomashi/services/myanimelist_client.dart';
import '../services/myanimelist_library_test.dart'
    show LibraryCredentials, libraryRow;

const captureMal = bool.fromEnvironment('YOMASHI_MAL_CAPTURE');
const malPreviewKey = ValueKey('mal-preview');
MalManga listed(int id, String title, String status) =>
    MalManga.fromMap(libraryRow(id: id, title: title, status: status));

class LibraryFake extends MyAnimeListClient {
  LibraryFake(LibraryCredentials store) : super(credentials: store);
  final calls = <(String, int, int?)>[];
  final errors = <String, Object>{};
  final pages = <(String, int), MalMangaPage>{
    ('reading', 0): MalMangaPage(
      items: [
        listed(1, 'Obra en lectura', 'reading'),
        listed(99, 'Ya completada', 'completed'),
      ],
    ),
    ('plan_to_read', 0): MalMangaPage(
      items: [listed(2, 'Obra por leer', 'plan_to_read')],
    ),
  };
  Future<MalMangaPage> Function(String status, int offset, int? owner)? handler;
  @override
  Future<Map<String, dynamic>?> account() => credentials.load();
  @override
  Future<MalMangaPage> library({
    required String status,
    int offset = 0,
    int limit = 50,
    int? expectedOwner,
  }) async {
    calls.add((status, offset, expectedOwner));
    if (handler != null) return handler!(status, offset, expectedOwner);
    if (errors[status] != null) throw errors[status]!;
    return pages[(status, offset)] ?? const MalMangaPage(items: []);
  }
}

class _UnavailableSource extends SourceProvider {
  @override
  bool get isLoaded => true;
  @override
  bool get isActiveImplemented => false;
}

class _HomeLibrary extends LibraryProvider {
  @override
  Future<void> flushStats() async {}
}

Future<void> loadMalPreviewFonts() async {
  if (!captureMal) return;
  final font = File(
    'C:/flutter/bin/cache/dart-sdk/bin/resources/devtools/assets/fonts/Roboto/Roboto-Regular.ttf',
  );
  final bytes = Future.value(ByteData.sublistView(font.readAsBytesSync()));
  await (FontLoader('Roboto')..addFont(bytes)).load();
  await (FontLoader('Ahem')..addFont(bytes)).load();
}

Future<void> captureMalPreview(WidgetTester tester, String name) async {
  if (!captureMal) return;
  final folder = Directory('build/reports/mal-library/ui');
  folder.createSync(recursive: true);
  await expectLater(
    find.byKey(malPreviewKey),
    matchesGoldenFile(File('${folder.path}/$name.png').absolute.uri),
  );
}

Widget malApp(Widget child, {double scale = 1}) => RepaintBoundary(
  key: malPreviewKey,
  child: MaterialApp(
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      textTheme: ThemeData.dark().textTheme.apply(
        fontFamily: captureMal ? 'Roboto' : null,
      ),
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: child,
  ),
);

void main() {
  setUpAll(loadMalPreviewFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> size(
    WidgetTester tester, {
    double width = 360,
    double height = 720,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'shows only reading and plan-to-read entries and opens the selected manga',
    (tester) async {
      await size(tester);
      final client = LibraryFake(LibraryCredentials());
      addTearDown(() => client.http.close(force: true));
      MalManga? opened;
      await tester.pumpWidget(
        malApp(
          MalLibraryScreen(client: client, onOpen: (manga) => opened = manga),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Obra en lectura'), findsOneWidget);
      expect(find.text('Obra por leer'), findsOneWidget);
      expect(find.text('Ya completada'), findsNothing);
      expect(client.calls.map((call) => call.$3), everyElement(7));
      await tester.tap(find.text('Obra por leer'));
      expect(opened!.id, 2);
      await captureMalPreview(tester, 'library');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Leyendo'));
      await tester.pumpAndSettle();
      expect(find.text('Obra por leer'), findsNothing);
      expect(find.text('Obra en lectura'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'loads more rows without duplicating mangas or reloading finished lists',
    (tester) async {
      final client = LibraryFake(LibraryCredentials());
      addTearDown(() => client.http.close(force: true));
      client.pages[('reading', 0)] = MalMangaPage(
        items: [listed(1, 'Primera obra', 'reading')],
        nextOffset: 1,
      );
      client.pages[('reading', 1)] = MalMangaPage(
        items: [
          listed(1, 'Primera obra', 'reading'),
          listed(3, 'Segunda obra', 'reading'),
        ],
      );
      await tester.pumpWidget(malApp(MalLibraryScreen(client: client)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Cargar más mangas'));
      await tester.tap(find.text('Cargar más mangas'));
      await tester.pumpAndSettle();
      expect(find.text('Primera obra'), findsOneWidget);
      expect(find.text('Segunda obra'), findsOneWidget);
      expect(
        client.calls.where((call) => call.$1 == 'plan_to_read'),
        hasLength(1),
      );
      expect(client.calls, contains(('reading', 1, 7)));
    },
  );

  testWidgets(
    'one status failure preserves the other list and offers a targeted retry',
    (tester) async {
      final client = LibraryFake(LibraryCredentials());
      addTearDown(() => client.http.close(force: true));
      client.errors['plan_to_read'] = const MalFailure('Error de prueba');
      await tester.pumpWidget(malApp(MalLibraryScreen(client: client)));
      await tester.pumpAndSettle();
      expect(find.text('Obra en lectura'), findsOneWidget);
      expect(find.textContaining('Error de prueba'), findsOneWidget);
      client.errors.clear();
      await tester.tap(find.text('Reintentar Por leer'));
      await tester.pumpAndSettle();
      expect(find.text('Obra por leer'), findsOneWidget);
      expect(client.calls.where((call) => call.$1 == 'reading'), hasLength(1));
    },
  );

  testWidgets('disconnect immediately removes account entries', (tester) async {
    final store = LibraryCredentials();
    final client = LibraryFake(store);
    addTearDown(() => client.http.close(force: true));
    await tester.pumpWidget(malApp(MalLibraryScreen(client: client)));
    await tester.pumpAndSettle();
    store.value = null;
    client.sessionChanges.value++;
    await tester.pumpAndSettle();
    expect(find.text('Obra en lectura'), findsNothing);
    expect(find.text('Obra por leer'), findsNothing);
    expect(find.textContaining('Vincula una cuenta'), findsOneWidget);
  });

  testWidgets('a delayed response cannot restore an earlier account list', (
    tester,
  ) async {
    final store = LibraryCredentials();
    final client = LibraryFake(store);
    addTearDown(() => client.http.close(force: true));
    final gate = Completer<MalMangaPage>();
    client.handler = (status, offset, owner) async {
      if (owner == 7 && status == 'reading') return gate.future;
      return MalMangaPage(
        items: owner == 8 && status == 'reading'
            ? [listed(8, 'Cuenta nueva', 'reading')]
            : [],
      );
    };
    await tester.pumpWidget(malApp(MalLibraryScreen(client: client)));
    await tester.pump();
    await tester.pump();
    store.value = {
      'connected': true,
      'device_token': 'new-fixture',
      'profile': {'id': 8, 'name': 'Other'},
    };
    client.sessionChanges.value++;
    await tester.pumpAndSettle();
    gate.complete(
      MalMangaPage(items: [listed(7, 'Cuenta anterior', 'reading')]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cuenta nueva'), findsOneWidget);
    expect(find.text('Cuenta anterior'), findsNothing);
  });

  testWidgets(
    'home places MAL right of sources only for a linked account at large text',
    (tester) async {
      await size(tester, width: 320, height: 640);
      final store = LibraryCredentials()..value = null;
      final client = LibraryFake(store);
      addTearDown(() => client.http.close(force: true));
      final profile = ProfileProvider(malClient: client);
      await profile.load();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: profile),
            ChangeNotifierProvider<LibraryProvider>(
              create: (_) => _HomeLibrary(),
            ),
            ChangeNotifierProvider<SourceProvider>(
              create: (_) => _UnavailableSource(),
            ),
          ],
          child: malApp(HomeScreen(malClient: client), scale: 1.6),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mangas MAL'), findsNothing);
      store.value = {
        'connected': true,
        'device_token': 'fixture-device',
        'profile': {'id': 7, 'name': 'Reader'},
      };
      client.sessionChanges.value++;
      await tester.pumpAndSettle();
      final source = tester.getRect(find.byTooltip('Cambiar fuente'));
      final mal = tester.getRect(
        find.widgetWithText(OutlinedButton, 'Mangas MAL'),
      );
      expect(mal.left, greaterThan(source.right));
      expect(mal.right, lessThanOrEqualTo(320));
      expect((mal.center.dy - source.center.dy).abs(), lessThan(2));
      expect(tester.takeException(), isNull);
      await captureMalPreview(tester, 'home-large-text');
      await tester.tap(find.text('Mangas MAL'));
      await tester.pumpAndSettle();
      expect(find.byType(MalLibraryScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      profile.dispose();
    },
  );

  testWidgets(
    'library remains usable with long titles and large text on a narrow phone',
    (tester) async {
      await size(tester, width: 320, height: 640);
      final client = LibraryFake(LibraryCredentials());
      addTearDown(() => client.http.close(force: true));
      client.pages[('reading', 0)] = MalMangaPage(
        items: [
          listed(
            1,
            'Un título de manga muy largo para comprobar la lectura y el espacio disponible',
            'reading',
          ),
        ],
      );
      await tester.pumpWidget(
        malApp(MalLibraryScreen(client: client), scale: 1.6),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await captureMalPreview(tester, 'library-large-text');
    },
  );
}
