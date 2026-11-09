import 'dart:async';
import 'package:flutter/material.dart';
import '../models/manga.dart';
import '../screens/myanimelist_screen.dart';
import '../services/myanimelist_service.dart';
import '../utils/network_errors.dart';
import '../utils/time_format.dart';

class MalSyncStatus extends StatefulWidget {
  final Manga manga;
  final MyAnimeListService? service;
  const MalSyncStatus({super.key, required this.manga, this.service});
  @override
  State<MalSyncStatus> createState() => _MalSyncStatusState();
}

class _MalSyncStatusState extends State<MalSyncStatus> {
  late final service = widget.service ?? MyAnimeListService.shared;
  Map<String, dynamic>? _state;
  bool _busy = false;
  String? _error;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    service.changes.addListener(_reload);
    service.client.sessionChanges.addListener(_sessionChanged);
    _reload();
  }

  @override
  void didUpdateWidget(MalSyncStatus old) {
    super.didUpdateWidget(old);
    if (MyAnimeListService.mangaKey(old.manga) !=
        MyAnimeListService.mangaKey(widget.manga)) {
      _state = null;
      _reload();
    }
  }

  @override
  void dispose() {
    _generation++;
    service.changes.removeListener(_reload);
    service.client.sessionChanges.removeListener(_sessionChanged);
    super.dispose();
  }

  void _sessionChanged() {
    if (mounted) {
      setState(() {
        _state = null;
        _error = null;
      });
    }
    _reload();
  }

  void _reload() {
    final gen = ++_generation;
    unawaited(
      service
          .statusFor(widget.manga)
          .then((state) {
            if (mounted && gen == _generation) {
              setState(() {
                _state = state;
                _error = null;
              });
            }
          })
          .catchError((Object error) {
            if (mounted && gen == _generation) {
              setState(() => _error = NetworkErrors.friendly(error));
            }
          }),
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await service.refreshManga(widget.manga);
    } catch (error) {
      if (mounted) setState(() => _error = NetworkErrors.friendly(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reload();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = _state?['link'] as Map?;
    final snapshot = _state?['snapshot'] as Map?;
    final pending = _state?['pending'] as Map?;
    final label = pending != null
        ? 'Pendiente: capítulo ${pending['chapters']}'
        : snapshot?['syncedAt'] != null &&
              snapshot?['sentChapters'] == snapshot?['chapters']
        ? 'Sincronizado: capítulo ${snapshot!['chapters']}'
        : snapshot != null
        ? 'En MyAnimeList: capítulo ${snapshot['chapters']}'
        : link != null
        ? 'Obra vinculada · Progreso aún sin consultar'
        : 'Vincular con MyAnimeList';
    final when = snapshot?['checkedAt'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            pending != null ? Icons.cloud_upload_outlined : Icons.sync_alt,
          ),
          title: Text(label),
          subtitle: Text(
            [
              if (link != null) '${link['malTitle']} · ID ${link['malId']}',
              if (snapshot != null)
                MyAnimeListScreen.statesLabel(snapshot['status'] as String?),
              if (when is int) 'Consultado: ${formatTimeAgo(when)}',
              if (snapshot?['syncedAt'] is int)
                'Último envío: capítulo ${snapshot!['sentChapters']} · ${formatTimeAgo(snapshot['syncedAt'] as int)}',
              if (pending?['error'] is String) pending!['error'] as String,
              if (link == null)
                'Revisa la obra y el progreso antes de activar la sincronización.',
            ].join('\n'),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    MyAnimeListScreen(manga: widget.manga, service: service),
              ),
            );
            if (mounted) _reload();
          },
        ),
        if (link != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
              label: Text(_busy ? 'Consultando…' : 'Consultar estado en MAL'),
            ),
          ),
        if (_error != null) Text(_error!),
      ],
    );
  }
}
