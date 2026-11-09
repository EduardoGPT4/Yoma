import 'package:yomashi/utils/permissions.dart';
import 'package:yomashi/services/maintenance_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/main.dart' as yoma;
import 'package:yomashi/features/anime/widgets/anime_widgets.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Profile: real Anime catalog navigation and scrolling', (
    tester,
  ) async {
    expect(const bool.fromEnvironment('YOMASHI_QA'), true);
    final info = await MaintenancePlatform.channel
        .invokeMapMethod<String, dynamic>('info');
    expect(
      info?['package'],
      const bool.fromEnvironment('YOMA_INTEGRATION_QA')
          ? 'app.yoma.integration.qa'
          : 'app.yomashi.reader.qa',
    );
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      'onboarding_completed_v1',
      'welcome_notice_seen_v1',
      'manage_storage_explained_v1',
    ]) {
      await prefs.setBool(key, true);
    }
    if (const bool.fromEnvironment('YOMA_INTEGRATION_QA')) {
      await StoragePermissionService.requestNotifications();
    }
    await yoma.main();
    for (var i = 0; i < 30 && find.text('Anime').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Anime'), findsOneWidget);
    await tester.tap(find.text('Anime'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Explorar'));
    await tester.pump(const Duration(seconds: 1));
    for (var i = 0; i < 90 && find.byType(AnimeCard).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(
      find.byType(AnimeCard),
      findsWidgets,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .join(' | '),
    );
    final grid = find.byType(CustomScrollView).hitTestable().first;
    await binding.watchPerformance(() async {
      for (var i = 0; i < 8; i++) {
        await tester.fling(grid, const Offset(0, -700), 1200);
        await tester.pump(const Duration(milliseconds: 450));
      }
      for (var i = 0; i < 8; i++) {
        await tester.fling(grid, const Offset(0, 700), 1200);
        await tester.pump(const Duration(milliseconds: 450));
      }
    }, reportKey: 'anime_catalog_scroll');
    await tester.tap(find.widgetWithText(TextButton, 'Yoma'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Anime'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Explorar'), findsOneWidget);
    binding.reportData ??= {};
    binding.reportData!['catalog_cards_mounted'] = find
        .byType(AnimeCard)
        .evaluate()
        .length;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
