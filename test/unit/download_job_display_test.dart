import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/models/chapter.dart';
import 'package:yomashi/models/download_job.dart';
import 'package:yomashi/models/online_manga.dart';

void main() {
  test('paused and failed downloads do not keep an obsolete ETA', () {
    final job = DownloadJob(
      id: 'display',
      manga: OnlineMangaDetail(
        title: 'Fixture',
        url: 'https://example.com/manga',
        chapters: [
          Chapter(title: '1', path: '/1', pages: const []),
          Chapter(title: '2', path: '/2', pages: const []),
        ],
      ),
      completedChapters: 1,
      startedAt: DateTime.now().subtract(const Duration(days: 7)),
      status: DownloadJobStatus.downloading,
    );
    expect(job.etaLabel, isNotNull);
    for (final status in DownloadJobStatus.values) {
      if (status == DownloadJobStatus.downloading) continue;
      job.status = status;
      expect(job.etaLabel, isNull, reason: status.name);
    }
  });
}
