import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/content_identity.dart';

class ThumbnailService {
  static final Map<String, Future<File?>> _pendingRequests = {};
  static final List<Completer<void>> _waiting = [];
  static int _active = 0;
  static int _requests = 0;
  static const quotaBytes = 64 * 1024 * 1024;
  static Future<File?> getThumbnail(String? sourcePath, {int size = 360}) {
    if (sourcePath == null || sourcePath.isEmpty) return Future.value(null);
    final key = '$sourcePath|$size';
    final existing = _pendingRequests[key];
    if (existing != null) return existing;
    final future = _resolve(sourcePath, size.clamp(32, 720));
    _pendingRequests[key] = future;
    // El error sigue perteneciendo al Future que espera el widget.
    unawaited(
      future.then<void>(
        (_) {
          _pendingRequests.remove(key);
        },
        onError: (Object _) {
          _pendingRequests.remove(key);
        },
      ),
    );
    return future;
  }

  static Future<void> _acquire() async {
    if (_active >= 2) {
      final waiter = Completer<void>();
      _waiting.add(waiter);
      await waiter.future;
    } else {
      _active++;
    }
  }

  static void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
    } else {
      _active--;
    }
  }

  static Future<File?> _resolve(String source, int size) async {
    final file = File(source);
    if (!await file.exists()) return null;
    final stat = await file.stat();
    final directory = await _directory();
    final target = File(
      p.join(
        directory.path,
        '${ContentIdentity.id('$source|${stat.size}|${stat.modified.millisecondsSinceEpoch}|$size')}.jpg',
      ),
    );
    if (await target.exists()) {
      unawaited(
        target.setLastModified(DateTime.now()).catchError((Object _) => target),
      );
      return target;
    }
    await _acquire();
    try {
      final bytes = await compute(_build, {'path': source, 'size': size});
      if (bytes == null) return null;
      final part = File('${target.path}.part');
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(target.path);
      if (++_requests % 24 == 0) unawaited(_trim());
      return target;
    } finally {
      _release();
    }
  }

  static Uint8List? _build(Map<String, dynamic> args) {
    final file = File(args['path'] as String);
    if (file.lengthSync() > 64 * 1024 * 1024) return null;
    final bytes = file.readAsBytesSync();
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info == null || info.width * info.height > 48 * 1024 * 1024) {
      return null;
    }
    final decoded = decoder!.decodeFrame(0);
    if (decoded == null) return null;
    final width = (args['size'] as int).clamp(1, decoded.width);
    final resized = img.copyResize(
      decoded,
      width: width,
      interpolation: img.Interpolation.average,
    );
    return Uint8List.fromList(img.encodeJpg(resized, quality: 82));
  }

  static Future<Directory> _directory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      p.join(support.path, 'manga_reader_cache', 'thumbnails'),
    );
    await directory.create(recursive: true);
    return directory;
  }

  static Future<int> cacheSize() async {
    var bytes = 0;
    await for (final file in (await _directory()).list(followLinks: false)) {
      if (file is File) bytes += await file.length();
    }
    return bytes;
  }

  static Future<void> clearCache() => _trim(clear: true);
  static Future<void> _trim({bool clear = false}) async {
    final files = <({File file, FileStat stat})>[];
    await for (final entry in (await _directory()).list(followLinks: false)) {
      if (entry is File && p.extension(entry.path) == '.jpg') {
        files.add((file: entry, stat: await entry.stat()));
      }
    }
    files.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
    var bytes = files.fold<int>(0, (n, e) => n + e.stat.size);
    for (final entry in files) {
      if (!clear && bytes <= quotaBytes) break;
      await entry.file.delete();
      bytes -= entry.stat.size;
    }
  }
}
