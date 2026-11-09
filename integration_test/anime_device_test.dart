import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'sample_video_fixture.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/features/anime/data/anime_controller.dart';
import 'package:yomashi/features/anime/data/local_anime_downloads.dart';
import 'package:yomashi/features/anime/models/anime_models.dart';
import 'package:yomashi/features/anime/screens/anime_player_screen.dart';
import 'package:yomashi/services/maintenance_service.dart';
import 'package:video_player/video_player.dart';

class OfflineTransferFixture extends LocalAnimeDownloads {
  int enqueues = 0;
  final String path;
  OfflineTransferFixture(this.path);
  @override
  Future<Map<String, dynamic>> snapshot() async => {
    'supported': true,
    'items': [
      {
        'slug': 'qa-video',
        'number': '1',
        'language': 'SUB',
        'state': 'done',
        'file': path,
        'total': 1,
      },
    ],
  };
  @override
  Future<void> enqueue(
    AnimeTitle anime,
    AnimeEpisode episode,
    String language,
  ) async {
    enqueues++;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android decodes offline MP4, seeks, persists and pauses without enqueue',
    (tester) async {
      expect(const bool.fromEnvironment('YOMASHI_QA'), true);
      final info = await MaintenancePlatform.channel
          .invokeMapMethod<String, dynamic>('info');
      expect(
        info?['package'],
        const bool.fromEnvironment('YOMA_INTEGRATION_QA')
            ? 'app.yoma.integration.qa'
            : 'app.yomashi.reader.qa',
      );
      final fixture = File(
        '${(await getApplicationSupportDirectory()).path}/sample-test-only.mp4',
      );
      await fixture.writeAsBytes(base64Decode(sampleMp4), flush: true);
      await LibraryStore.initialize();
      final transfers = OfflineTransferFixture(fixture.path);
      final app = AnimeController(transfers: transfers);
      await app.refreshDownloads();
      final detail = AnimeDetail.fromJson({
        'anime': {'slug': 'qa-video', 'title': 'Test video'},
        'episodes': [
          {'id': 1, 'slug': 'qa-video', 'number': '1'},
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: AnimePlayerScreen(
            controller: app,
            detail: detail,
            episode: detail.episodes.first,
            openWeb: (_) => fail('Offline playback must not open the web'),
          ),
        ),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while (find.byType(VideoPlayer).evaluate().isEmpty &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(
        find.byType(VideoPlayer),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '),
      );
      final video = tester
          .widget<VideoPlayer>(find.byType(VideoPlayer))
          .controller;
      expect(video.value.isInitialized, true);
      expect(video.value.duration.inSeconds, greaterThan(20));
      await video.play();
      await tester.pump(const Duration(seconds: 1));
      await video.seekTo(const Duration(seconds: 12));
      await tester.pump(const Duration(seconds: 1));
      app.setActive(false);
      await tester.pump(const Duration(seconds: 1));
      expect(video.value.isPlaying, false);
      expect(
        app.positions[detail.episodes.first.key]?['positionMs'],
        greaterThanOrEqualTo(12000),
      );
      expect(transfers.enqueues, 0);
      final stored = await app.store.progress();
      expect(
        stored.any(
          (row) =>
              row['slug'] == 'qa-video' && (row['positionMs'] as int) >= 12000,
        ),
        true,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      app.dispose();
    },
  );
}
