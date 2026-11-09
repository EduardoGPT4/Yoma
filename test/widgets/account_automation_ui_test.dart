import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/screens/automation_screen.dart';
import 'package:yomashi/screens/myanimelist_screen.dart';
import 'package:yomashi/screens/profile_screen.dart';
import 'package:yomashi/models/ui_density.dart';
import 'package:yomashi/providers/density_provider.dart';
import 'package:yomashi/providers/download_queue_provider.dart';
import 'package:yomashi/providers/library_provider.dart';
import 'package:yomashi/providers/profile_provider.dart';
import 'package:yomashi/providers/reader_settings_provider.dart';
import 'package:yomashi/services/myanimelist_client.dart';
import 'package:yomashi/services/myanimelist_service.dart';
import 'profile_myanimelist_test.dart' show ProfileTestLibrary;

class _UiCredentials extends MalCredentialStore {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> load() async => value;
  @override
  Future<void> save(Map<String, dynamic> next) async => value = next;
  @override
  Future<void> clear() async => value = null;
}

class _UiMalClient extends MyAnimeListClient {
  _UiMalClient(_UiCredentials store) : super(credentials: store);
  var starts = 0;
  @override
  Future<Map<String, dynamic>?> account() => credentials.load();
  @override
  Future<Map<String, dynamic>> begin() async {
    starts++;
    return (await credentials.load())!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryStore library;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    library = await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
  });
  setUp(() async => library.replaceRecords('mal_pending', []));

  test('automation dates distinguish today, yesterday and previous years', () {
    final now = DateTime(2026, 10, 28, 10, 45);
    String label(DateTime date) =>
        AutomationDisplay.timestamp(date.millisecondsSinceEpoch, now: now);
    expect(label(DateTime(2026, 10, 28, 9, 26, 18, 405)), 'Hoy, 09:26');
    expect(label(DateTime(2026, 10, 27, 20, 29)), 'Ayer, 20:29');
    expect(label(DateTime(2026, 10, 20, 8, 5)), '20/10, 08:05');
    expect(label(DateTime(2025, 10, 20, 8, 5)), '20/10/2025, 08:05');
    expect(AutomationDisplay.timestamp(0, now: now), 'Sin registrar');
    expect(
      AutomationDisplay.timestamp(
        DateTime(2026, 12, 31, 23, 50).millisecondsSinceEpoch,
        now: DateTime(2027, 1, 1, 1),
      ),
      'Ayer, 23:50',
    );
  });

  test('automation budget labels simplify units without changing values', () {
    expect(AutomationDisplay.budget(512), '512 MB');
    expect(AutomationDisplay.budget(1024), '1 GB');
    expect(AutomationDisplay.budget(1536), '1,5 GB');
    expect(AutomationDisplay.budget(2048), '2 GB');
    expect(AutomationDisplay.budget(8192), '8 GB');
    expect(
      AutomationDisplay.backupDate(
        File('/backups/yomashi_backup_unknown.json'),
      ),
      'Fecha desconocida',
    );
  });

  Future<void> settleAccount(WidgetTester tester) async {
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('disconnected MAL shows connection before search and sync', (
    tester,
  ) async {
    final credentials = _UiCredentials();
    final client = _UiMalClient(credentials);
    addTearDown(() => client.http.close(force: true));
    addTearDown(client.sessionChanges.dispose);
    await tester.pumpWidget(
      MaterialApp(home: MyAnimeListScreen(service: MyAnimeListService(client))),
    );
    await settleAccount(tester);
    expect(find.text('Conectar cuenta'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('Envíos pendientes:'), findsNothing);
    expect(find.text('Reintentar envíos pendientes'), findsNothing);
    expect(find.text('Actualizar conexión'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'pending authorization reopens its URL without replacing session',
    (tester) async {
      const url =
          'https://hk-br035.gt.tc/seasonav1/yomashi-connect.php?device=fixture';
      final credentials = _UiCredentials()
        ..value = {
          'connected': false,
          'device_token': 'fixture',
          'code': '123456',
          'connect_url': url,
        };
      final client = _UiMalClient(credentials);
      addTearDown(() => client.http.close(force: true));
      addTearDown(client.sessionChanges.dispose);
      final opened = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MalPlatform.channel, (call) async {
            if (call.method == 'openBrowser') {
              opened.add(call.arguments as String);
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(MalPlatform.channel, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MyAnimeListScreen(service: MyAnimeListService(client)),
        ),
      );
      await settleAccount(tester);
      expect(find.text('Continuar autorización'), findsOneWidget);
      expect(find.text('Iniciar otra conexión'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Continuar autorización'));
      await tester.pumpAndSettle();
      expect(opened, [url]);
      expect(client.starts, 0);
      expect(credentials.value!['device_token'], 'fixture');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('connected MAL shows search and hides an empty retry action', (
    tester,
  ) async {
    final credentials = _UiCredentials()
      ..value = {
        'connected': true,
        'device_token': 'fixture',
        'profile': {'id': 7, 'name': 'MangaReader'},
      };
    final client = _UiMalClient(credentials);
    addTearDown(() => client.http.close(force: true));
    addTearDown(client.sessionChanges.dispose);
    await tester.pumpWidget(
      MaterialApp(home: MyAnimeListScreen(service: MyAnimeListService(client))),
    );
    await settleAccount(tester);
    expect(find.text('Conectado como MangaReader'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Sin envíos pendientes'), findsOneWidget);
    expect(find.text('Reintentar envíos pendientes'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('profile puts identity first and density wraps with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final credentials = _UiCredentials()
      ..value = {
        'connected': true,
        'profile': {'id': 7, 'name': 'MangaReader'},
      };
    final client = _UiMalClient(credentials);
    final profile = ProfileProvider(malClient: client);
    await profile.load();
    await profile.refreshMyAnimeList();
    final library = ProfileTestLibrary();
    final downloads = DownloadQueueProvider(useNative: true);
    final settings = ReaderSettingsProvider();
    final density = DensityProvider();
    addTearDown(() {
      library.dispose();
      downloads.dispose();
      settings.dispose();
      density.dispose();
      profile.dispose();
      client.http.close(force: true);
      client.sessionChanges.dispose();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ProfileProvider>.value(value: profile),
          ChangeNotifierProvider<LibraryProvider>.value(value: library),
          ChangeNotifierProvider<DownloadQueueProvider>.value(value: downloads),
          ChangeNotifierProvider<ReaderSettingsProvider>.value(value: settings),
          ChangeNotifierProvider<DensityProvider>.value(value: density),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('MangaReader')).dy,
      lessThan(tester.getTopLeft(find.text('MyAnimeList · Manga')).dy),
    );
    expect(find.text('Densidad'), findsNothing);
    await tester.tap(find.byTooltip('Ajustes'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Buscar ajustes'),
      'densidad',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Densidad'));
    await tester.ensureVisible(find.text('Cómoda'));
    await tester.tap(find.text('Cómoda'));
    await tester.pumpAndSettle();
    expect(density.density, UiDensity.comfortable);
    await tester.ensureVisible(
      find.widgetWithText(TextFormField, 'Buscar ajustes'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Buscar ajustes'),
      'brillo',
    );
    await tester.pumpAndSettle();
    expect(find.text('Densidad'), findsNothing);
    expect(find.text('Brillo en la app'), findsOneWidget);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
