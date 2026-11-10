import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/widgets/storage_migration_screen.dart';

void main() {
  for (final (size, scale) in [
    (const Size(412, 915), 1.0),
    (const Size(320, 560), 1.6),
  ]) {
    testWidgets('migration screen fits $size at ${scale}x text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: const StorageMigrationApp(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Organizando tus archivos'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
