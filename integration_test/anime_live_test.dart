import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yomashi/features/anime/data/local_anime_downloads.dart';
import 'package:yomashi/features/anime/data/yomatv_source.dart';
import 'package:yomashi/features/anime/models/anime_models.dart';
import 'package:yomashi/services/maintenance_service.dart';
import 'package:video_player/video_player.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Live public source resolves and plays a compatible server without web login',
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
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Yoma live source verification')),
        ),
      );
      final source = YomaTvSource();
      final transfers = LocalAnimeDownloads();
      final failures = <String>[];
      bool played = false;
      try {
        final catalog = AnimePage.fromJson(await source.catalog());
        expect(catalog.items, isNotEmpty);
        for (final anime in catalog.items.take(3)) {
          VideoPlayerController? video;
          try {
            final detail = AnimeDetail.fromJson(
              await source.detail(anime.slug),
            );
            if (detail.episodes.isEmpty) continue;
            final episode = detail.episodes.first;
            final servers = await transfers.sources(anime, episode);
            final compatible = servers.where((s) => s.supported).toList();
            if (compatible.isEmpty) {
              failures.add('${anime.slug}: no compatible server');
              continue;
            }
            final stream = await transfers.resolve(
              anime,
              episode,
              compatible.first.language,
              embed: compatible.first.embed,
            );
            video = VideoPlayerController.networkUrl(
              stream.url,
              httpHeaders: stream.headers,
            );
            await video.initialize().timeout(const Duration(seconds: 30));
            await video.setVolume(0);
            await video.play();
            for (
              var i = 0;
              i < 20 && video.value.position.inMilliseconds == 0;
              i++
            ) {
              await tester.pump(const Duration(milliseconds: 250));
            }
            expect(video.value.position.inMilliseconds, greaterThan(0));
            await video.pause();
            played = true;
            binding.reportData = {
              ...?binding.reportData,
              'anime_slug': anime.slug,
              'server': stream.server,
              'duration_ms': video.value.duration.inMilliseconds,
              'source_catalog_total': catalog.total,
              'no_web_login': true,
            };
            break;
          } catch (error) {
            failures.add('${anime.slug}: $error');
          } finally {
            await video?.dispose();
          }
        }
        expect(played, true, reason: failures.join('\n'));
      } finally {
        source.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
