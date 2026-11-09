import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../services/image_repository.dart';

/// A separate persistent thumbnail cache; never contains episode media.
class AnimeCover extends ImageProvider<AnimeCover> {
  final String url;
  const AnimeCover(this.url);
  static final _repository = ImageRepository()..quotaBytes = 64 * 1024 * 1024;
  static Future<void>? _ready;
  static Future<void> _initialize() async {
    final root = await getApplicationSupportDirectory();
    _repository.cacheDirectory = Directory(
      p.join(root.path, 'Yoma', 'YomaTV', 'Miniaturas'),
    );
  }

  @override
  Future<AnimeCover> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(AnimeCover key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);
  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
      throw const FormatException('Portada no válida');
    }
    await (_ready ??= _initialize());
    final file = await _repository.resolve(url);
    return decode(
      await ui.ImmutableBuffer.fromUint8List(await file.readAsBytes()),
    );
  }

  @override
  bool operator ==(Object other) => other is AnimeCover && url == other.url;
  @override
  int get hashCode => url.hashCode;
}
