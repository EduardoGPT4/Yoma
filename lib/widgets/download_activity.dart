import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/download_queue_provider.dart';
import '../utils/title_sanitizer.dart';

class DownloadActivity extends StatelessWidget {
  const DownloadActivity({super.key});
  static bool pending(DownloadJob job) => const {
    DownloadJobStatus.queued,
    DownloadJobStatus.downloading,
    DownloadJobStatus.paused,
    DownloadJobStatus.failed,
  }.contains(job.status);
  static String label(DownloadJob job) => switch (job.status) {
    DownloadJobStatus.downloading =>
      '${job.completedChapters}/${job.totalChapters} capítulos · Descargando',
    DownloadJobStatus.paused => job.error ?? 'Pausada por ti',
    DownloadJobStatus.failed =>
      job.error ?? 'Descarga interrumpida. Puedes reintentar.',
    _ => job.error ?? 'En cola · Esperando turno',
  };
  static void show(BuildContext context) {
    final provider = context.read<DownloadQueueProvider>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: provider,
        child: const _DownloadSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final jobs = context
        .watch<DownloadQueueProvider>()
        .jobs
        .where(pending)
        .toList();
    if (jobs.isEmpty) return const SizedBox.shrink();
    final active = jobs.firstWhere(
      (j) => j.status == DownloadJobStatus.downloading,
      orElse: () => jobs.first,
    );
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        dense: true,
        minTileHeight: 48,
        leading: const Icon(Icons.downloading_outlined),
        title: Text(
          TitleSanitizer.clean(active.manga.title),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          label(active),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.expand_less),
        onTap: () => show(context),
      ),
    );
  }
}

class _DownloadSheet extends StatelessWidget {
  const _DownloadSheet();
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DownloadQueueProvider>();
    final jobs = provider.jobs.where(DownloadActivity.pending).toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .6,
        child: Column(
          children: [
            Text(
              'Descargas (${jobs.length})',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (provider.persistenceError != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(provider.persistenceError!),
              ),
            if (jobs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Todas las descargas han terminado.'),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: jobs.length,
                itemBuilder: (context, index) {
                  final job = jobs[index];
                  final canResume =
                      job.status == DownloadJobStatus.paused ||
                      job.status == DownloadJobStatus.failed;
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          TitleSanitizer.clean(job.manga.title),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(DownloadActivity.label(job)),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: job.progress,
                          semanticsLabel: 'Capítulos descargados',
                          semanticsValue: '${(job.progress * 100).round()} %',
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => canResume
                                ? provider.resumeJob(job.id)
                                : provider.pauseJob(job.id),
                            icon: Icon(
                              canResume ? Icons.play_arrow : Icons.pause,
                            ),
                            label: Text(canResume ? 'Reanudar' : 'Pausar'),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
