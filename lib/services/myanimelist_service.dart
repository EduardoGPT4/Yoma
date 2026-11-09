import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/library_store.dart';
import '../models/chapter.dart';
import '../models/content_identity.dart';
import '../models/manga.dart';
import '../utils/preferences.dart';
import 'myanimelist_client.dart';

/// The local reading state is authoritative locally; MAL failures never undo it.
class MyAnimeListService {
  static final shared = MyAnimeListService(MyAnimeListClient());
  final MyAnimeListClient client;
  final changes = ValueNotifier<int>(0);
  Future<void>? _flushing;
  MyAnimeListService(this.client);
  static String mangaKey(Manga m) =>
      ContentIdentity.canonical(m.sourceUrl ?? m.path);
  static int? chapterNumber(Chapter chapter) {
    final value =
        chapter.number ??
        RegExp(
          r'cap(?:[íi]tulo|\.)?\s*0*(\d+(?:\.\d+)?)',
          caseSensitive: false,
        ).firstMatch(chapter.title)?.group(1) ??
        (RegExp(r'^\d+(?:\.\d+)?$').hasMatch(chapter.title.trim())
            ? chapter.title.trim()
            : null);
    final n = double.tryParse(value ?? '');
    return n != null &&
            n.isFinite &&
            n >= 1 &&
            n <= 100000 &&
            n == n.floorToDouble()
        ? n.toInt()
        : null;
  }

  Future<Map<String, dynamic>?> linkFor(Manga manga) async {
    final value = await (await LibraryStore.ensureInitialized()).getRecord(
      'mal_links',
      mangaKey(manga),
    );
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  Future<Map<String, dynamic>> statusFor(Manga manga) async {
    final auth = await client.credentials.load();
    final owner = (auth?['profile'] as Map?)?['id'];
    final mapping = await linkFor(manga);
    if (auth?['connected'] != true ||
        mapping == null ||
        mapping['owner'] != owner) {
      return {'connected': auth?['connected'] == true};
    }
    final store = await LibraryStore.ensureInitialized();
    final snapshot = await store.getRecord('mal_sync', mangaKey(manga));
    final pending = await store.getRecord('mal_pending', mangaKey(manga));
    bool current(dynamic row) =>
        row is Map &&
        row['owner'] == owner &&
        row['version'] == mapping['version'];
    return {
      'connected': true,
      'link': mapping,
      if (current(snapshot)) 'snapshot': snapshot,
      if (current(pending)) 'pending': pending,
    };
  }

  Future<void> recordSnapshot(
    Manga manga,
    MalManga value, {
    bool sent = false,
    int? expectedOwner,
    String? expectedToken,
    int? expectedVersion,
  }) async {
    final auth = await client.credentials.load();
    final owner = (auth?['profile'] as Map?)?['id'];
    if (auth?['connected'] != true ||
        owner is! int ||
        (expectedOwner != null && owner != expectedOwner) ||
        (expectedToken != null && auth?['device_token'] != expectedToken)) {
      return;
    }
    final store = await LibraryStore.ensureInitialized();
    final key = mangaKey(manga);
    await store.transaction(() async {
      final link = await store.getRecord('mal_links', key);
      if (link is! Map ||
          link['owner'] != owner ||
          link['malId'] != value.id ||
          (expectedVersion != null && link['version'] != expectedVersion)) {
        return;
      }
      final previous = await store.getRecord('mal_sync', key);
      final now = DateTime.now().millisecondsSinceEpoch;
      await store.putRecord('mal_sync', key, {
        'id': key,
        'owner': owner,
        'version': link['version'],
        'chapters': value.chaptersRead,
        'status': value.status,
        'checkedAt': now,
        if (sent) ...{
          'syncedAt': now,
          'sentChapters': value.chaptersRead,
        } else if (previous is Map &&
            previous['version'] == link['version'] &&
            previous['owner'] == owner) ...{
          'syncedAt': previous['syncedAt'],
          'sentChapters': previous['sentChapters'],
        },
      });
    });
    changes.value++;
  }

  Future<void> refreshManga(Manga manga) async {
    final state = await statusFor(manga);
    final link = state['link'];
    if (link is! Map) return;
    final session = await client.credentials.load();
    final value = await client.detail(link['malId'] as int);
    await recordSnapshot(
      manga,
      value,
      expectedOwner: link['owner'] as int,
      expectedVersion: link['version'] as int,
      expectedToken: session?['device_token'] as String?,
    );
  }

  Future<void> link(
    Manga manga,
    MalManga selected, {
    required bool automatic,
    int? expectedOwner,
  }) async {
    final auth = await client.credentials.load();
    final owner = (auth?['profile'] as Map?)?['id'];
    if (owner is! int || auth?['connected'] != true) {
      throw const MalFailure('Conecta tu cuenta antes de vincular una obra.');
    }
    if (expectedOwner != null && owner != expectedOwner) {
      throw const MalFailure(
        'La cuenta cambió. Vuelve a seleccionar el manga.',
        409,
      );
    }
    final store = await LibraryStore.ensureInitialized();
    final key = mangaKey(manga);
    await store.transaction(() async {
      await store.deleteRecord('mal_pending', key);
      await store.putRecord('mal_links', key, {
        'id': key,
        'manga': key,
        'title': manga.title,
        'malId': selected.id,
        'malTitle': selected.title,
        'owner': owner,
        'automatic': automatic,
        'version': DateTime.now().microsecondsSinceEpoch,
      });
    });
    await registerManga(manga);
    await recordSnapshot(manga, selected, expectedOwner: owner);
    changes.value++;
    if (automatic) {
      final reads = await PreferencesService.getReadChapterKeys();
      Chapter? latest;
      var highest = 0;
      for (final chapter in manga.chapters) {
        final n = chapterNumber(chapter) ?? 0;
        if ((reads.contains(chapter.path) ||
                reads.contains(chapter.sourceUrl)) &&
            n > highest) {
          highest = n;
          latest = chapter;
        }
      }
      if (latest != null) await queueRead(latest.sourceUrl ?? latest.path);
    }
  }

  Future<void> unlink(Manga manga) async {
    final store = await LibraryStore.ensureInitialized();
    final key = mangaKey(manga);
    await store.transaction(() async {
      await store.deleteRecord('mal_links', key);
      await store.deleteRecord('mal_pending', key);
      await store.deleteRecord('mal_sync', key);
    });
    changes.value++;
  }

  Future<void> registerManga(Manga manga, {Iterable<Chapter>? chapters}) async {
    final link = await linkFor(manga);
    if (link == null) return;
    final store = await LibraryStore.ensureInitialized();
    final list = (chapters ?? manga.chapters).toList();
    for (var start = 0; start < list.length; start += 100) {
      await store.transaction(() async {
        for (final chapter in list.skip(start).take(100)) {
          final number = chapterNumber(chapter);
          if (number == null) continue;
          final record = {'manga': mangaKey(manga), 'chapter': number};
          await store.putRecord(
            'mal_chapters',
            ContentIdentity.canonical(chapter.path),
            record,
          );
          if (chapter.sourceUrl != null) {
            await store.putRecord(
              'mal_chapters',
              ContentIdentity.canonical(chapter.sourceUrl!),
              record,
            );
          }
        }
      });
    }
  }

  Future<void> queueRead(String path) async {
    final store = await LibraryStore.ensureInitialized();
    final chapter = await store.getRecord(
      'mal_chapters',
      ContentIdentity.canonical(path),
    );
    if (chapter is! Map) return;
    final auth = await client.credentials.load();
    final owner = (auth?['profile'] as Map?)?['id'];
    await store.transaction(() async {
      final link = await store.getRecord(
        'mal_links',
        chapter['manga'] as String,
      );
      if (link is! Map ||
          link['automatic'] != true ||
          owner == null ||
          link['owner'] != owner ||
          auth?['connected'] != true) {
        return;
      }
      final id = link['id'] as String;
      final old = await store.getRecord('mal_pending', id);
      final before =
          old is Map &&
              old['owner'] == owner &&
              old['version'] == link['version']
          ? (old['chapters'] as int)
          : 0;
      final count = chapter['chapter'] as int;
      if (before >= count) return;
      await store.putRecord('mal_pending', id, {
        'id': id,
        'owner': owner,
        'malId': link['malId'],
        'version': link['version'],
        'chapters': count > before ? count : before,
        'lease': old?['lease'] ?? 0,
        'tries': 0,
        'retryAt': 0,
      });
    });
    changes.value++;
  }

  Future<void> flush({bool force = false}) {
    if (_flushing != null) return _flushing!;
    final work = _flush(force: force);
    _flushing = work;
    return work.whenComplete(() {
      _flushing = null;
      changes.value++;
    });
  }

  Future<void> _flush({required bool force}) async {
    final store = await LibraryStore.ensureInitialized();
    if ((await store.readRecords('mal_pending')).isEmpty) return;
    final auth = await client.credentials.load();
    final owner = (auth?['profile'] as Map?)?['id'];
    if (auth?['connected'] != true || owner is! int) return;
    for (var pass = 0; pass < 3; pass++) {
      var sent = false;
      var claimed = 0;
      for (final record in await store.readRecords('mal_pending')) {
        if (claimed >= 10) break;
        Map<String, dynamic>? job;
        final now = DateTime.now().millisecondsSinceEpoch;
        await store.transaction(() async {
          final current = await store.getRecord(
            'mal_pending',
            record['id'] as String,
          );
          if (current is! Map ||
              current['owner'] != owner ||
              (current['lease'] as int? ?? 0) > now ||
              (!force &&
                  ((current['tries'] as int? ?? 0) >= 5 ||
                      (current['retryAt'] as int? ?? 0) > now))) {
            return;
          }
          final link = await store.getRecord(
            'mal_links',
            record['id'] as String,
          );
          if (link is! Map ||
              link['automatic'] != true ||
              link['owner'] != owner ||
              link['version'] != current['version'] ||
              link['malId'] != current['malId']) {
            return;
          }
          job = Map<String, dynamic>.from(current)..['lease'] = now + 90000;
          await store.putRecord('mal_pending', record['id'] as String, job);
        });
        if (job == null) continue;
        claimed++;
        try {
          final session = await client.credentials.load();
          if ((session?['profile'] as Map?)?['id'] != owner ||
              session?['connected'] != true) {
            return;
          }
          final result = await client.update(
            job!['malId'] as int,
            job!['chapters'] as int,
            'reading',
            automatic: true,
            expectedOwner: owner,
          );
          final mapping = await store.getRecord(
            'mal_links',
            record['id'] as String,
          );
          if (mapping is Map && mapping['version'] == job!['version']) {
            await recordSnapshot(
              Manga(
                title: mapping['title'] as String? ?? '',
                path: record['id'] as String,
                chapters: const [],
              ),
              result,
              sent: true,
              expectedOwner: owner,
              expectedVersion: job!['version'] as int,
              expectedToken: session?['device_token'] as String?,
            );
          }
          await store.transaction(() async {
            final current = await store.getRecord(
              'mal_pending',
              record['id'] as String,
            );
            if (current is! Map || current['version'] != job!['version']) {
              return;
            }
            if (current['chapters'] == job!['chapters']) {
              await store.deleteRecord('mal_pending', record['id'] as String);
            } else {
              await store.putRecord('mal_pending', record['id'] as String, {
                ...current,
                'lease': 0,
              });
            }
          });
          sent = true;
        } catch (e) {
          await store.transaction(() async {
            final current = await store.getRecord(
              'mal_pending',
              record['id'] as String,
            );
            if (current is! Map || current['version'] != job!['version']) {
              return;
            }
            final tries = (current['tries'] as int? ?? 0) + 1;
            await store.putRecord('mal_pending', record['id'] as String, {
              ...current,
              'lease': 0,
              'tries': tries,
              'retryAt': now + (10000 * (1 << tries.clamp(0, 8))),
              'error': e is MalFailure
                  ? e.message
                  : 'No se pudo enviar el progreso a MyAnimeList.',
            });
          });
          return;
        }
      }
      if (!sent) break;
    }
  }
}
