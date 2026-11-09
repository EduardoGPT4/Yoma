import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yomashi/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'welcome_notice_seen_v1': true,
      'onboarding_completed_v1': true,
    });
  });

  testWidgets('renders the main app shell', (tester) async {
    await tester.pumpWidget(const MangaReaderApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // La shell de la app monta HomeScreen / MaterialApp sin crash.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
