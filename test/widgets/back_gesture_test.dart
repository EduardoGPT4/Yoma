import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/design/yoma_theme.dart';
import 'package:yomashi/design/yoma_tokens.dart';
import 'package:yomashi/widgets/app_metrics.dart';

/// Gesto atrás de Android 16 (predictivo): el sistema avisa del inicio, del
/// avance y de la confirmación por el canal `flutter/backgesture`.
Future<void> _swipeBack(WidgetTester tester) async {
  Future<void> send(String method, [Object? args]) =>
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/backgesture',
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
        (_) {},
      );
  const event = {
    'touchOffset': [4.0, 400.0],
    'progress': 0.0,
    'swipeEdge': 0,
  };
  await send('startBackGesture', event);
  await send('updateBackGestureProgress', {...event, 'progress': .7});
  await send('commitBackGesture');
  await tester.pumpAndSettle();
}

void main() {
  // Igual que YomaShell: cada sección tiene su Navigator y el raíz reparte
  // el «atrás»; la pantalla completa del video va en el Navigator raíz.
  Future<GlobalKey<NavigatorState>> pumpShell(WidgetTester tester) async {
    final section = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomaTheme(
          YomaColors.accent,
          AppMetrics.compact,
        ).copyWith(platform: TargetPlatform.android),
        home: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) section.currentState!.maybePop();
          },
          child: Navigator(
            key: section,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Descargas')),
            ),
          ),
        ),
      ),
    );
    return section;
  }

  void open(NavigatorState navigator, String name) => navigator.push(
    MaterialPageRoute<void>(builder: (_) => Scaffold(body: Text(name))),
  );

  testWidgets('un gesto atrás quita la pantalla completa y nada más', (
    tester,
  ) async {
    final section = await pumpShell(tester);
    open(section.currentState!, 'Episodios descargados');
    await tester.pumpAndSettle();
    open(section.currentState!, 'Reproductor');
    await tester.pumpAndSettle();
    final root = tester.state<NavigatorState>(find.byType(Navigator).first);
    root.push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) =>
            const Scaffold(body: Text('Video a pantalla completa')),
      ),
    );
    await tester.pumpAndSettle();

    await _swipeBack(tester);

    expect(find.text('Video a pantalla completa'), findsNothing);
    expect(find.text('Reproductor'), findsOneWidget);

    await _swipeBack(tester);
    expect(find.text('Reproductor'), findsNothing);
    expect(find.text('Episodios descargados'), findsOneWidget);
  });

  testWidgets('un gesto atrás cierra el reproductor o el lector', (
    tester,
  ) async {
    final section = await pumpShell(tester);
    open(section.currentState!, 'Lector');
    await tester.pumpAndSettle();

    await _swipeBack(tester);

    expect(find.text('Lector'), findsNothing);
    expect(find.text('Descargas'), findsOneWidget);
  });
}
