import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/design/yoma_theme.dart';
import 'package:yomashi/utils/preferences.dart';
import 'package:yomashi/widgets/app_metrics.dart';
import 'package:yomashi/widgets/permissions_screen.dart';

/// Permisos simulados: "Ajustes" concede el acceso a archivos al volver.
class FakeBackend extends AppPermissionBackend {
  bool storage = false, notifications = false, blocked = false;
  final calls = <String>[];
  @override
  Future<AppPermissionState> read() async => AppPermissionState(
    storage: storage,
    notifications: notifications,
    notificationsBlocked: blocked,
  );
  @override
  Future<void> requestStorage() async {
    calls.add('storage');
    storage = true;
  }

  @override
  Future<void> requestNotifications() async {
    calls.add('notifications');
    notifications = true;
  }

  @override
  Future<void> openSettings() async => calls.add('settings');
}

Future<void> _open(WidgetTester tester, FakeBackend backend) async {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildYomaTheme(const Color(0xFFF0848D), AppMetrics.compact),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PermissionsScreen(backend: backend),
            ),
          ),
          child: const Text('abrir'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('storage is requested on every launch; notifications only once', () {
    const missingStorage = AppPermissionState(
      storage: false,
      notifications: true,
    );
    const missingNotifications = AppPermissionState(
      storage: true,
      notifications: false,
    );
    const complete = AppPermissionState(storage: true, notifications: true);
    expect(PermissionsGate.shouldShow(missingStorage, asked: true), isTrue);
    expect(
      PermissionsGate.shouldShow(missingNotifications, asked: false),
      isTrue,
    );
    expect(
      PermissionsGate.shouldShow(missingNotifications, asked: true),
      isFalse,
    );
    expect(PermissionsGate.shouldShow(complete, asked: false), isFalse);
  });

  testWidgets('allow all grants both permissions and then offers Continue', (
    tester,
  ) async {
    final backend = FakeBackend();
    await _open(tester, backend);
    expect(find.text('Permisos de Yoma'), findsOneWidget);
    expect(find.text('Necesario'), findsOneWidget);
    expect(find.text('Permitir'), findsNWidgets(2));
    expect(find.textContaining('no se pueden descargar'), findsOneWidget);

    await tester.tap(find.text('Permitir todo'));
    await tester.pumpAndSettle();
    expect(backend.calls, ['storage', 'notifications']);
    expect(find.text('Concedido'), findsNWidgets(2));
    expect(find.textContaining('no se pueden descargar'), findsNothing);
    expect(await PreferencesService.getNotificationsAsked(), isTrue);

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Permisos de Yoma'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('blocked notifications open the app settings', (tester) async {
    final backend = FakeBackend()
      ..storage = true
      ..blocked = true;
    await _open(tester, backend);
    await tester.tap(find.text('Abrir ajustes'));
    await tester.pumpAndSettle();
    expect(backend.calls, ['settings']);
  });

  testWidgets('not now closes the screen and records the answer', (
    tester,
  ) async {
    final backend = FakeBackend();
    await _open(tester, backend);
    await tester.tap(find.text('Ahora no'));
    await tester.pumpAndSettle();
    expect(find.text('Permisos de Yoma'), findsNothing);
    expect(backend.calls, isEmpty);
    expect(await PreferencesService.getNotificationsAsked(), isTrue);
  });

  testWidgets('returning from Android settings refreshes the real state', (
    tester,
  ) async {
    final backend = FakeBackend();
    await _open(tester, backend);
    backend.storage = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Concedido'), findsOneWidget);
  });
}
