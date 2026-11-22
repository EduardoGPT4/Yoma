import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/library_store.dart';
import '../models/manga.dart';
import '../services/myanimelist_client.dart';
import '../services/myanimelist_service.dart';

class MyAnimeListScreen extends StatefulWidget {
  final Manga? manga;
  final MyAnimeListService? service;

  /// Abre directamente la autorización si aún no hay cuenta conectada (desde
  /// «Iniciar sesión con MyAnimeList» al abrir la app).
  final bool autoConnect;
  const MyAnimeListScreen({
    super.key,
    this.manga,
    this.service,
    this.autoConnect = false,
  });
  static String statesLabel(String? value) => switch (value) {
    'reading' => 'Leyendo',
    'completed' => 'Completado',
    'on_hold' => 'En pausa',
    'dropped' => 'Abandonado',
    'plan_to_read' => 'Por leer',
    _ => 'Sin estado',
  };
  @override
  State<MyAnimeListScreen> createState() => _MyAnimeListScreenState();
}

class _MyAnimeListScreenState extends State<MyAnimeListScreen>
    with WidgetsBindingObserver {
  static const states = {
    'reading': 'Leyendo',
    'completed': 'Completado',
    'on_hold': 'En pausa',
    'dropped': 'Abandonado',
    'plan_to_read': 'Por leer',
  };
  late final service = widget.service ?? MyAnimeListService.shared;
  late final query = TextEditingController(text: widget.manga?.title ?? '');
  Map<String, dynamic>? account, link;
  List<Map<String, dynamic>> pending = [];
  List<MalManga> results = [];
  MalManga? selected;
  String? error;
  bool busy = false, automatic = false, _polling = false;
  int generation = 0;
  Timer? timer;
  bool get connected => account?['connected'] == true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(
      _refresh().then((_) {
        if (widget.autoConnect && mounted && !connected && !busy) {
          unawaited(_connect());
        }
      }),
    );
    timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted &&
          !busy &&
          !connected &&
          account != null &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(_refresh());
      }
    });
  }

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    query.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_polling || !mounted) return;
    _polling = true;
    try {
      final next = await service.client.account();
      final mapping = widget.manga == null
          ? null
          : await service.linkFor(widget.manga!);
      final jobs = await (await LibraryStore.ensureInitialized()).readRecords(
        'mal_pending',
      );
      if (mounted) {
        final before = (account?['profile'] as Map?)?['id'];
        final after = (next?['profile'] as Map?)?['id'];
        setState(() {
          if (before != after) {
            generation++;
            results = [];
            selected = null;
          }
          account = next;
          link = mapping;
          pending = jobs.where((j) => j['owner'] == after).toList();
          automatic = mapping?['automatic'] == true;
          if (next?['connected'] == true) error = null;
        });
        if (next?['connected'] == true) {
          unawaited(
            service.flush().catchError((Object e) {
              if (mounted) {
                setState(
                  () => error =
                      'No se pudo sincronizar. Reintenta los envíos pendientes.',
                );
              }
            }),
          );
        }
      }
    } catch (e) {
      final current = e is MalFailure && e.status == 401
          ? await service.client.credentials.load()
          : account;
      if (mounted) {
        setState(() {
          error = e.toString();
          account = current;
          if (current == null) {
            generation++;
            results = [];
            selected = null;
          }
        });
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      final current = e is MalFailure && e.status == 401
          ? await service.client.credentials.load()
          : account;
      if (mounted) {
        setState(() {
          error = e.toString();
          account = current;
          if (current == null) {
            generation++;
            results = [];
            selected = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _search() async {
    final current = ++generation;
    await _run(() async {
      final values = await service.client.search(query.text);
      if (mounted && current == generation) {
        setState(() {
          results = values;
          selected = null;
        });
      }
    });
  }

  Future<void> _connect({bool restart = false}) => _run(() async {
    final existing = restart ? null : account;
    final session = existing?['connect_url'] is String
        ? existing!
        : await service.client.begin();
    if (!mounted) return;
    setState(() => account = session);
    await MalPlatform.openBrowser(session['connect_url'] as String);
  });

  /// Abre la obra elegida en una ventana emergente para revisar su estado
  /// y confirmar el vínculo, sin desplazarse por la pantalla.
  Future<void> _select(MalManga manga) async {
    MalManga? detail;
    int? owner;
    await _run(() async {
      detail = await service.client.detail(manga.id);
      final auth = await service.client.credentials.load();
      owner = (auth?['profile'] as Map?)?['id'] as int?;
    });
    final chosen = detail;
    if (!mounted || chosen == null) return;
    setState(() {
      selected = chosen;
    });
    final linked = await showDialog<bool>(
      context: context,
      builder: (_) => _MalLinkDialog(
        service: service,
        manga: widget.manga,
        chosen: chosen,
        owner: owner,
        automatic: automatic,
      ),
    );
    if (!mounted) return;
    if (linked == true) {
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vínculo guardado')));
    }
  }

  Future<void> _disconnect() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Desconectar MyAnimeList'),
        content: const Text(
          'Se revocará la conexión de este dispositivo. La biblioteca y el progreso local se conservan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _run(() async {
        try {
          await service.client.disconnect();
        } on MalFailure catch (failure) {
          // Sin respuesta del servidor (estado 0) se permite olvidar aquí.
          if (failure.status != 0 || !await _confirmForget()) rethrow;
          await service.client.forgetLocally();
        }
        generation++;
        if (mounted) {
          setState(() {
            account = null;
            results = [];
            selected = null;
          });
        }
      });
    }
  }

  Future<bool> _confirmForget() async {
    if (!mounted) return false;
    final forget = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sin conexión con el servidor'),
        content: const Text(
          'No se pudo revocar la conexión. ¿Quieres olvidar la cuenta solo en '
          'este dispositivo? La sesión del servidor caducará si no se usa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Olvidar aquí'),
          ),
        ],
      ),
    );
    return forget == true;
  }

  @override
  Widget build(BuildContext context) {
    final chosen = selected;
    return Scaffold(
      appBar: AppBar(title: const Text('MyAnimeList · Manga')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    connected
                        ? 'Conectado como ${(account!['profile'] as Map)['name']}'
                        : 'Conecta tu cuenta de MyAnimeList',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sincroniza tus capítulos leídos y el estado de tus mangas.',
                  ),
                  if (!connected && account != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'Código: ${account!['code'] ?? ''}\nAutoriza en el navegador y vuelve a YomaShi. La conexión se comprobará automáticamente.',
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (!connected)
                        FilledButton(
                          onPressed: busy ? null : _connect,
                          child: Text(
                            account == null
                                ? 'Conectar cuenta'
                                : 'Continuar autorización',
                          ),
                        ),
                      if (connected)
                        TextButton(
                          onPressed: busy ? null : _disconnect,
                          child: const Text('Desconectar'),
                        ),
                      if (account != null)
                        TextButton(
                          onPressed: busy ? null : _refresh,
                          child: const Text('Actualizar conexión'),
                        ),
                      if (!connected && account != null)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => _connect(restart: true),
                          child: const Text('Iniciar otra conexión'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (connected) ...[
            const SizedBox(height: 20),
            Text(
              'Buscar en MyAnimeList',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (widget.manga != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Obra local: ${widget.manga!.title}\n${link == null ? 'Toca un resultado para revisarlo y confirmar el vínculo.' : 'Vínculo: ${link!['malTitle']} · ID ${link!['malId']}${link!['automatic'] == true ? ' · envía tu progreso' : ''}'}',
                ),
              ),
            if (link != null)
              TextButton.icon(
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Revisar progreso de la obra vinculada'),
                onPressed: busy
                    ? null
                    : () => _select(
                        MalManga(
                          id: link!['malId'] as int,
                          title: link!['malTitle'] as String,
                          chaptersRead: 0,
                          totalChapters: 0,
                          status: 'reading',
                          publishingStatus: '',
                        ),
                      ),
              ),
            TextField(
              controller: query,
              enabled: connected && !busy,
              decoration: const InputDecoration(
                labelText: 'Nombre, ID o enlace de manga',
                helperText: 'Por ejemplo: One Piece o 13',
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: connected && !busy ? _search : null,
              icon: const Icon(Icons.search),
              label: const Text('Buscar manga'),
            ),
            for (final manga in results)
              ListTile(
                title: Text(manga.title),
                subtitle: Text(
                  'MAL ${manga.id} · ${manga.totalChapters == 0 ? 'Capítulos sin confirmar' : '${manga.totalChapters} capítulos'}',
                ),
                selected: chosen?.id == manga.id,
                onTap: busy ? null : () => _select(manga),
              ),
            if (link != null)
              TextButton(
                onPressed: busy
                    ? null
                    : () => _run(() async {
                        await service.unlink(widget.manga!);
                        await _refresh();
                      }),
                child: const Text('Desvincular esta obra'),
              ),
            const SizedBox(height: 16),
            if (pending.isEmpty)
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.cloud_done_outlined),
                title: Text('Sin envíos pendientes'),
              ),
            if (pending.isNotEmpty) ...[
              Text('Envíos pendientes: ${pending.length}'),
              for (final job in pending)
                if (job['error'] is String)
                  Text('MAL ${job['malId']}: ${job['error']}'),
              TextButton.icon(
                onPressed: connected && !busy
                    ? () => _run(() async {
                        await service.flush(force: true);
                        await _refresh();
                      })
                    : null,
                icon: const Icon(Icons.sync),
                label: const Text('Reintentar envíos pendientes'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Ventana emergente con la obra de MAL elegida: estado, capítulos leídos,
/// envío automático y confirmación del vínculo.
class _MalLinkDialog extends StatefulWidget {
  final MyAnimeListService service;
  final Manga? manga;
  final MalManga chosen;
  final int? owner;
  final bool automatic;
  const _MalLinkDialog({
    required this.service,
    required this.manga,
    required this.chosen,
    required this.owner,
    required this.automatic,
  });

  @override
  State<_MalLinkDialog> createState() => _MalLinkDialogState();
}

class _MalLinkDialogState extends State<_MalLinkDialog> {
  late MalManga chosen = widget.chosen;
  late String status = _MyAnimeListScreenState.states.containsKey(chosen.status)
      ? chosen.status
      : 'reading';
  late final chapters = TextEditingController(
    text: chosen.chaptersRead.toString(),
  );
  // Un vínculo nuevo envía el progreso, como los automáticos; se puede apagar.
  late bool automatic = widget.automatic || widget.manga != null;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    chapters.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _save() => _run(() async {
    final count = int.tryParse(chapters.text);
    if (count == null) {
      throw const MalFailure('Indica un número de capítulos válido.');
    }
    final saved = await widget.service.client.update(
      chosen.id,
      count,
      status,
      expectedOwner: widget.owner,
    );
    if (widget.manga != null) {
      await widget.service.recordSnapshot(
        widget.manga!,
        saved,
        sent: true,
        expectedOwner: widget.owner,
      );
    }
    if (!mounted) return;
    setState(() => chosen = saved);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Actualizado en MyAnimeList')));
  });

  Future<void> _link() => _run(() async {
    await widget.service.link(
      widget.manga!,
      chosen,
      automatic: automatic,
      expectedOwner: widget.owner,
    );
    if (mounted) Navigator.of(context).pop(true);
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(chosen.title),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'MyAnimeList ID ${chosen.id} · ${chosen.totalChapters == 0 ? 'capítulos sin confirmar' : '${chosen.totalChapters} capítulos'}',
            style: theme.textTheme.bodySmall,
          ),
          if (busy) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: status,
            decoration: const InputDecoration(labelText: 'Estado de lectura'),
            items: [
              for (final entry in _MyAnimeListScreenState.states.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: busy ? null : (v) => setState(() => status = v!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: chapters,
            enabled: !busy,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Capítulos leídos'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: busy ? null : _save,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Guardar en MyAnimeList'),
            ),
          ),
          if (widget.manga != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enviar progreso al terminar capítulos'),
              subtitle: const Text(
                'Conserva el mayor progreso y los estados en pausa o abandonado.',
              ),
              value: automatic,
              onChanged: busy ? null : (v) => setState(() => automatic = v),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(false),
          child: Text(widget.manga == null ? 'Cerrar' : 'Cancelar'),
        ),
        if (widget.manga != null)
          FilledButton(
            onPressed: busy ? null : _link,
            child: const Text('Confirmar vínculo'),
          ),
      ],
    );
  }
}
