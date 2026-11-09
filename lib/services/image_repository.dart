import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/content_identity.dart';
import '../utils/app_failure.dart';
import '../utils/download_rate_limiter.dart';
import 'source_http_client.dart';
import 'storage_metrics.dart';
import '../data/library_store.dart';

class ImageRepository {
  static final shared = ImageRepository();
  final SourceHttpClient client;
  final Map<String, Future<File>> _pending = {};
  final Map<String, String> _offline = {};
  Directory? cacheDirectory;
  int quotaBytes = 256 * 1024 * 1024;
  int? _cachedBytes;
  double latencyMs = 600;
  Future<void> _trimming = Future.value();
  ImageRepository({SourceHttpClient? client})
    : client =
          client ??
          SourceHttpClient(
            bodyTimeout: const Duration(hours: 2),
            maxBodyBytes: 128 * 1024 * 1024,
          );

  void registerOffline(String url, String path) {
    _offline[url] = path;
    final store = LibraryStore.current;
    if (store != null) {
      unawaited(
        store
            .putRecord('image_offline', ContentIdentity.id(url), {
              'url': url,
              'path': path,
            })
            .catchError((Object error) {
              stderr.writeln('Índice de imágenes: $error');
            }),
      );
    }
  }

  Future<Directory> _directory() async {
    final directory = cacheDirectory ??= Directory(
      p.join((await getTemporaryDirectory()).path, 'yomashi_images'),
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> resolve(
    String url, {
    Map<String, String>? headers,
    bool refresh = false,
  }) async {
    final store = LibraryStore.current;
    final saved = store == null
        ? null
        : await store.getRecord('image_offline', ContentIdentity.id(url));
    final offline = _offline[url] ?? saved?['path'] as String?;
    if (offline != null && await valid(File(offline))) return File(offline);
    final directory = await _directory();
    _cachedBytes ??= await cacheSize();
    final file = File(
      p.join(directory.path, '${ContentIdentity.id(url)}.image'),
    );
    if (!refresh && await valid(file)) {
      unawaited(
        file.setLastModified(DateTime.now()).catchError((Object _) => file),
      );
      return file;
    }
    if (_pending.containsKey(url)) return _pending[url]!;
    final previousBytes = await file.exists() ? await file.length() : 0;
    if (_pending.containsKey(url)) return _pending[url]!;
    final future = download(url, file, headers: headers).then((_) => file);
    _pending[url] = future;
    final clock = Stopwatch()..start();
    try {
      final result = await future;
      latencyMs = latencyMs * .7 + clock.elapsedMilliseconds * .3;
      _cachedBytes =
          (_cachedBytes ?? 0) + await result.length() - previousBytes;
      if (_cachedBytes! > quotaBytes) {
        unawaited(
          trim().catchError((Object error) {
            stderr.writeln('Caché: $error');
          }),
        );
      }
      return result;
    } finally {
      _pending.remove(url);
    }
  }

  Future<int> download(
    String url,
    File target, {
    Map<String, String>? headers,
    CancellationToken? cancellation,
    DownloadRateLimiter? limiter,
    void Function(int bytes)? onBytes,
  }) async {
    cancellation?.check();
    await target.parent.create(recursive: true);
    final request = await client.getUrl(Uri.parse(url));
    headers?.forEach(request.headers.set);
    request.headers.set('Accept', 'image/webp,image/jpeg,image/png,image/gif');
    final removeAbort = cancellation?.onCancel(
      () => request.abort(
        const AppFailure(FailureKind.cancelled, 'Transferencia cancelada.'),
      ),
    );
    StreamIterator<List<int>>? iterator;
    void Function()? removeCancel;
    final part = File('${target.path}.part');
    RandomAccessFile? output;
    var received = 0;
    try {
      final response = await request.close();
      cancellation?.check();
      final mime = response.headers.contentType?.mimeType ?? '';
      if (mime.contains('html') ||
          mime.contains('json') ||
          mime.startsWith('text/')) {
        throw const AppFailure(
          FailureKind.parsing,
          'El servidor no devolvió una imagen.',
        );
      }
      await StorageMetrics.requireSpace(
        target.parent.path,
        response.contentLength > 0 ? response.contentLength : 1024 * 1024,
      );
      if (response.contentLength > 128 * 1024 * 1024) {
        throw const AppFailure(
          FailureKind.parsing,
          'Una imagen supera el límite de 128 MiB.',
        );
      }
      output = await part.open(mode: FileMode.write);
      iterator = StreamIterator(response);
      removeCancel = cancellation?.onCancel(
        () => unawaited(iterator!.cancel()),
      );
      while (await iterator.moveNext()) {
        final chunk = iterator.current;
        for (var offset = 0; offset < chunk.length; offset += 16384) {
          cancellation?.check();
          final end = (offset + 16384).clamp(0, chunk.length);
          await limiter?.consume(end - offset, cancellation: cancellation);
          cancellation?.check();
          if (received + end - offset > 128 * 1024 * 1024) {
            throw const AppFailure(
              FailureKind.parsing,
              'Una imagen supera el límite de 128 MiB.',
            );
          }
          await output.writeFrom(chunk, offset, end);
          received += end - offset;
          onBytes?.call(end - offset);
        }
      }
      cancellation?.check();
      await output.flush();
      await output.close();
      output = null;
      if ((response.compressionState !=
                  HttpClientResponseCompressionState.decompressed &&
              response.contentLength >= 0 &&
              response.contentLength != received) ||
          !await valid(part)) {
        throw const AppFailure(
          FailureKind.parsing,
          'Imagen incompleta o formato no válido.',
        );
      }
      await part.rename(target.path);
      return received;
    } catch (error) {
      cancellation?.check();
      throw AppFailure.from(error);
    } finally {
      removeAbort?.call();
      removeCancel?.call();
      await iterator?.cancel();
      request.abort();
      await output?.close();
      if (await part.exists()) await part.delete();
    }
  }

  static Future<bool> valid(File file) async {
    if (!await file.exists()) return false;
    final length = await file.length();
    if (length < 12) return false;
    final input = await file.open();
    try {
      final head = await input.read(32);
      await input.setPosition(length > 16 ? length - 16 : 0);
      final tail = await input.read(16);
      if (head[0] == 0xff && head[1] == 0xd8) {
        return tail[tail.length - 2] == 0xff && tail.last == 0xd9;
      }
      if (head[0] == 137 && head[1] == 80 && head[2] == 78 && head[3] == 71) {
        return tail.length >= 12 &&
            String.fromCharCodes(
                  tail.sublist(tail.length - 8, tail.length - 4),
                ) ==
                'IEND';
      }
      if (String.fromCharCodes(head.take(4)) == 'RIFF' &&
          String.fromCharCodes(head.skip(8).take(4)) == 'WEBP') {
        return ByteData.sublistView(
                  Uint8List.fromList(head),
                ).getUint32(4, Endian.little) +
                8 ==
            length;
      }
      return String.fromCharCodes(head.take(3)) == 'GIF' && tail.last == 0x3b;
    } finally {
      await input.close();
    }
  }

  Future<int> cacheSize() async {
    final directory = await _directory();
    if (!await directory.exists()) return 0;
    var bytes = 0;
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is File) bytes += await entry.length();
    }
    return bytes;
  }

  Future<void> trim({bool clear = false}) {
    final next = _trimming.then((_) => _trim(clear: clear));
    _trimming = next.catchError((Object _) {});
    return next;
  }

  Future<void> _trim({bool clear = false}) async {
    final directory = await _directory();
    if (!await directory.exists()) return;
    final files = <({File file, FileStat stat})>[];
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is File && p.extension(entry.path) == '.image') {
        files.add((file: entry, stat: await entry.stat()));
      }
    }
    files.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
    var bytes = files.fold<int>(0, (sum, e) => sum + e.stat.size);
    for (final item in files) {
      if (!clear && bytes <= quotaBytes) break;
      if (_pending.keys.any(
        (url) =>
            p.basename(item.file.path) == '${ContentIdentity.id(url)}.image',
      )) {
        continue;
      }
      await item.file.delete();
      bytes -= item.stat.size;
    }
    _cachedBytes = bytes;
  }
}
