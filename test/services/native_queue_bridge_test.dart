import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/models/chapter.dart';
import 'package:yomashi/models/online_manga.dart';
import 'package:yomashi/providers/download_queue_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.yomashi.reader/downloads');
  test(
    'native queue applies compact progress without losing manga metadata',
    () async {
      final job = DownloadJob(
        id: 'native',
        manga: const OnlineMangaDetail(
          title: 'Fixture',
          url: 'https://inmanga.com/a',
          chapters: [
            Chapter(
              title: 'One',
              path: 'https://inmanga.com/chapter/a',
              pages: [],
              pageCount: 0,
            ),
          ],
        ),
      );
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return {
              'jobs': [job.toMap()],
              'archive': [],
              'root': '/storage/Mangas',
              'threads': 3,
              'wifi': false,
              'limit': 0,
            };
          });
      final provider = DownloadQueueProvider(useNative: true);
      await provider.load();
      final progress = job.toMap(includeManga: false)
        ..['receivedBytes'] = 4096
        ..['completedPages'] = 1;
      final message = const StandardMethodCodec().encodeMethodCall(
        MethodCall('progress', {
          'jobs': [progress],
        }),
      );
      final done = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(channel.name, message, (_) {
            done.complete();
          });
      await done.future;
      expect(provider.jobs.single.receivedBytes, 4096);
      expect(provider.jobs.single.manga.title, 'Fixture');
      await provider.pauseForManga(job.manga.url);
      expect(calls, contains('pauseManga'));
      provider.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
}
