import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/models/automation_settings.dart';
import 'package:yomashi/providers/download_queue_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.yomashi.reader/downloads');
  final calls = <String>[];

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return <String, dynamic>{};
        });
  });

  setUp(calls.clear);

  Future<void> saveAhead(int count) async =>
      (await LibraryStore.ensureInitialized()).putRecord(
        'automation',
        'settings',
        AutomationSettings(aheadCount: count).toMap(),
      );

  test('sin descarga anticipada no despierta el servicio', () async {
    await saveAhead(0);
    final queue = DownloadQueueProvider(useNative: true);
    await queue.prepareAhead('https://example.com/m', 'https://example.com/c');
    expect(calls, isEmpty);
    queue.dispose();
  });

  test('con descarga anticipada sí envía la orden al servicio', () async {
    await saveAhead(3);
    final queue = DownloadQueueProvider(useNative: true);
    await queue.prepareAhead('https://example.com/m', 'https://example.com/c');
    expect(calls, ['ahead']);
    queue.dispose();
  });
}
