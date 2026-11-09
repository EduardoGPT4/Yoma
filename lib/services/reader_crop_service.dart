import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/content_identity.dart';

/// Solo procesa imágenes cuando el usuario activa el recorte; nunca altera el original.
class ReaderCropService {
  static final Map<String, Future<File>> _pending = {};
  static Future<void> _tail = Future.value();
  static Future<Directory> directory() async =>
      Directory(p.join((await getTemporaryDirectory()).path, 'reader_crops'));
  static Future<File> crop(File source) async {
    final stat = await source.stat();
    final id = ContentIdentity.id(
      '${source.path}|${stat.size}|${stat.modified.millisecondsSinceEpoch}|1',
    );
    if (_pending[id] != null) return _pending[id]!;
    // Un decodificador a la vez: una página de 24 MP puede ocupar 96 MB.
    final task = _tail.then((_) => _crop(source, id));
    _tail = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _pending[id] = task;
    try {
      return await task;
    } finally {
      _pending.remove(id);
    }
  }

  static Future<File> _crop(File source, String id) async {
    if (await source.length() > 32 * 1024 * 1024) return source;
    final dir = await directory();
    await dir.create(recursive: true);
    final target = File(p.join(dir.path, '$id.png'));
    if (await target.exists()) return target;
    final sourcePath = source.path;
    final data = await Isolate.run(() => process(sourcePath));
    if (data == null) return source;
    final part = File('${target.path}.part');
    try {
      await part.writeAsBytes(data, flush: true);
      await part.rename(target.path);
    } finally {
      if (await part.exists()) await part.delete();
    }
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.png'))
        .cast<File>()
        .toList();
    var total = 0;
    final dates = <String, DateTime>{};
    for (final f in files) {
      total += await f.length();
      dates[f.path] = await f.lastModified();
    }
    files.sort((a, b) => dates[a.path]!.compareTo(dates[b.path]!));
    for (final f in files) {
      if (total <= 32 * 1024 * 1024) break;
      if (f.path == target.path ||
          _pending.keys.any((k) => p.basenameWithoutExtension(f.path) == k)) {
        continue;
      }
      total -= await f.length();
      await f.delete();
    }
    return target;
  }

  static Uint8List? process(String path) {
    final bytes = File(path).readAsBytesSync();
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info == null ||
        info.width * info.height > 24 * 1000 * 1000 ||
        info.numFrames > 1) {
      return null;
    }
    final image = decoder!.decodeFrame(0);
    if (image == null) return null;
    final preview = img.copyResize(
      image,
      width: image.width > 512 ? 512 : image.width,
    );
    bool white(img.Pixel c) => c.r >= 245 && c.g >= 245 && c.b >= 245;
    bool row(int y) =>
        List.generate(
          preview.width,
          (x) => white(preview.getPixel(x, y)),
        ).where((e) => e).length >=
        preview.width * .995;
    bool column(int x) =>
        List.generate(
          preview.height,
          (y) => white(preview.getPixel(x, y)),
        ).where((e) => e).length >=
        preview.height * .995;
    var left = 0,
        right = preview.width - 1,
        top = 0,
        bottom = preview.height - 1;
    while (top < preview.height * .24 && row(top)) {
      top++;
    }
    while (bottom > preview.height * .76 && row(bottom)) {
      bottom--;
    }
    while (left < preview.width * .24 && column(left)) {
      left++;
    }
    while (right > preview.width * .76 && column(right)) {
      right--;
    }
    if (left + top + preview.width - 1 - right + preview.height - 1 - bottom <
            3 ||
        row(preview.height ~/ 2)) {
      return null;
    }
    final sx = image.width / preview.width, sy = image.height / preview.height;
    return img.encodePng(
      img.copyCrop(
        image,
        x: (left * sx).floor(),
        y: (top * sy).floor(),
        width: ((right - left + 1) * sx).ceil().clamp(
          1,
          image.width - (left * sx).floor(),
        ),
        height: ((bottom - top + 1) * sy).ceil().clamp(
          1,
          image.height - (top * sy).floor(),
        ),
      ),
    );
  }
}
