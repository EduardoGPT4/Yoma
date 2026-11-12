import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design/yoma_tokens.dart';
import '../data/anime_controller.dart';
import '../models/anime_models.dart';
import '../widgets/anime_widgets.dart';

/// Horario de emisión de la temporada, por días, como el apartado Temporada
/// de la web de YomaTV. Usa el catálogo público: no necesita cuenta.
class AnimeScheduleScreen extends StatefulWidget {
  final AnimeController controller;
  final ValueChanged<String> detail;

  /// Hoy, para elegir la pestaña inicial (sustituible en pruebas).
  final DateTime? today;
  const AnimeScheduleScreen({
    super.key,
    required this.controller,
    required this.detail,
    this.today,
  });

  static const days = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  /// «Próximo: hoy 21:30» para una emisión estimada en los próximos días.
  static String? nextLabel(Object? epochSeconds, DateTime now) {
    final seconds = epochSeconds is num ? epochSeconds.toInt() : null;
    if (seconds == null || seconds <= 0) return null;
    final at = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    final days = DateTime(
      at.year,
      at.month,
      at.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
    if (at.isBefore(now) || days > 7) return null;
    final time =
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final day = switch (days) {
      0 => 'hoy',
      1 => 'mañana',
      _ => AnimeScheduleScreen.days[at.weekday - 1].toLowerCase(),
    };
    return 'Próximo: $day $time (estimado)';
  }

  @override
  State<AnimeScheduleScreen> createState() => _AnimeScheduleScreenState();
}

class _AnimeScheduleScreenState extends State<AnimeScheduleScreen> {
  AnimeController get app => widget.controller;

  @override
  void initState() {
    super.initState();
    unawaited(app.loadSchedule());
  }

  @override
  Widget build(BuildContext context) {
    final today = (widget.today ?? DateTime.now()).weekday;
    return DefaultTabController(
      length: 7,
      initialIndex: today - 1,
      child: AnimatedBuilder(
        animation: app,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            title: const Text('Horario de emisión'),
            actions: [
              IconButton(
                tooltip: 'Actualizar horario',
                onPressed: app.scheduleLoading
                    ? null
                    : () => unawaited(app.loadSchedule(refresh: true)),
                icon: const Icon(Icons.refresh),
              ),
            ],
            bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                for (var day = 1; day <= 7; day++)
                  Tab(
                    text: [
                      day == today ? 'Hoy' : AnimeScheduleScreen.days[day - 1],
                      if (app.schedule.isNotEmpty)
                        '${app.scheduleFor(day).length}',
                    ].join(' · '),
                  ),
              ],
            ),
          ),
          body: Column(
            children: [
              if (app.scheduleLoading)
                const LinearProgressIndicator(minHeight: 2),
              if (app.scheduleError != null && app.schedule.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    app.scheduleError!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              Expanded(
                child: app.schedule.isEmpty
                    ? (app.scheduleLoading
                          ? const SizedBox.shrink()
                          : AnimeMessage(
                              app.scheduleError ??
                                  'No hay anime en emisión esta temporada.',
                              action: 'Reintentar',
                              onAction: () =>
                                  unawaited(app.loadSchedule(refresh: true)),
                            ))
                    : TabBarView(
                        children: [
                          for (var day = 1; day <= 7; day++) _day(day),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _day(int day) {
    final items = app.scheduleFor(day);
    if (items.isEmpty) {
      return const AnimeMessage('Ningún estreno este día.');
    }
    final now = widget.today ?? DateTime.now();
    return ListView.separated(
      key: PageStorageKey('anime-schedule-$day'),
      padding: const EdgeInsets.symmetric(vertical: YomaSpacing.sm),
      itemCount: items.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: YomaSpacing.xs),
      itemBuilder: (context, i) {
        if (i == items.length) {
          return Padding(
            padding: const EdgeInsets.all(YomaSpacing.lg),
            child: Text(
              'Días y horas según AnimeAV1; pueden cambiar.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }
        final anime = items[i];
        return _ScheduleTile(
          anime: anime,
          next: AnimeScheduleScreen.nextLabel(anime.raw['next_airing'], now),
          favorite: app.isFavorite(anime.slug),
          onTap: () => widget.detail(anime.slug),
        );
      },
    );
  }
}

class _ScheduleTile extends StatelessWidget {
  final AnimeTitle anime;
  final String? next;
  final bool favorite;
  final VoidCallback onTap;
  const _ScheduleTile({
    required this.anime,
    required this.next,
    required this.favorite,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final latest = '${anime.raw['latest'] ?? ''}';
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: YomaSpacing.lg),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(YomaRadii.sm),
        child: SizedBox(
          width: 48,
          height: 68,
          child: animeArtwork(anime.cover, width: 120),
        ),
      ),
      title: Text(anime.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          latest.isEmpty ? anime.category : 'Episodio $latest',
          ?next,
        ].join('\n'),
      ),
      trailing: favorite
          ? const Icon(
              Icons.star_rounded,
              color: YomaColors.rating,
              semanticLabel: 'Favorito',
            )
          : const Icon(Icons.chevron_right),
    );
  }
}
