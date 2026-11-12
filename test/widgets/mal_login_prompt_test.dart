import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/design/yoma_theme.dart';
import 'package:yomashi/design/yoma_tokens.dart';
import 'package:yomashi/services/myanimelist_client.dart';
import 'package:yomashi/widgets/app_metrics.dart';
import 'package:yomashi/widgets/mal_login_prompt.dart';

class _Credentials extends MalCredentialStore {
  Map<String, dynamic>? value;
  _Credentials([this.value]);
  @override
  Future<Map<String, dynamic>?> load() async => value;
  @override
  Future<void> save(Map<String, dynamic> value) async => this.value = value;
  @override
  Future<void> clear() async => value = null;
}

void main() {
  late int logins;
  late List<bool> shown;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    logins = 0;
    shown = [];
  });

  final boundary = GlobalKey();

  Future<void> open(WidgetTester tester, MalCredentialStore credentials) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final font = File(
        '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts/segoeui.ttf',
      );
      if (await font.exists()) {
        await (FontLoader(
          'Roboto',
        )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
      }
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomaTheme(YomaColors.accent, AppMetrics.compact),
        builder: (context, child) =>
            RepaintBoundary(key: boundary, child: child),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => shown.add(
                await MalLoginPrompt.maybeShow(
                  context,
                  credentials: credentials,
                  onLogin: () => logins++,
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('sin cuenta se propone una sola vez y se puede seguir en local', (
    tester,
  ) async {
    await open(tester, _Credentials());
    expect(find.text('Entra con tu MyAnimeList'), findsOneWidget);
    expect(find.text('Iniciar sesión con MyAnimeList'), findsOneWidget);
    // Para revisarla: build/test_screenshots/mal_login_prompt.png
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/test_screenshots').create(recursive: true);
      await File(
        'build/test_screenshots/mal_login_prompt.png',
      ).writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
    await tester.tap(find.text('Continuar sin cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Entra con tu MyAnimeList'), findsNothing);
    expect(shown, [true]);
    expect(logins, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(MalLoginPrompt.askedKey), isTrue);

    // En el siguiente inicio ya no vuelve a preguntar.
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Entra con tu MyAnimeList'), findsNothing);
    expect(shown, [true, false]);
  });

  testWidgets('iniciar sesión abre la conexión con MyAnimeList', (
    tester,
  ) async {
    await open(tester, _Credentials());
    await tester.tap(find.text('Iniciar sesión con MyAnimeList'));
    await tester.pumpAndSettle();
    expect(find.text('Entra con tu MyAnimeList'), findsNothing);
    expect(logins, 1);
  });

  testWidgets('cerrarla sin elegir cuenta como seguir sin cuenta', (
    tester,
  ) async {
    await open(tester, _Credentials());
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Entra con tu MyAnimeList'), findsNothing);
    expect(logins, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(MalLoginPrompt.askedKey), isTrue);
  });

  testWidgets('con MyAnimeList ya conectado no pregunta', (tester) async {
    await open(
      tester,
      _Credentials({
        'device_token': 'device',
        'connected': true,
        'profile': {'id': 7, 'name': 'Tester'},
      }),
    );
    expect(find.text('Entra con tu MyAnimeList'), findsNothing);
    expect(shown, [false]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(MalLoginPrompt.askedKey), isTrue);
  });

  testWidgets('una conexión empezada pero sin terminar sí pregunta', (
    tester,
  ) async {
    await open(
      tester,
      _Credentials({'device_token': 'device', 'connected': false}),
    );
    expect(find.text('Entra con tu MyAnimeList'), findsOneWidget);
  });
}
