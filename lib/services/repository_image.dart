import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'image_repository.dart';
import 'online_catalog_service.dart';
import 'reader_crop_service.dart';

class CroppedReaderImage extends ImageProvider<CroppedReaderImage> {
  final String path;
  const CroppedReaderImage(this.path);
  @override
  Future<CroppedReaderImage> obtainKey(ImageConfiguration c) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
    CroppedReaderImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);
  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final source = path.startsWith('http')
        ? await ImageRepository.shared.resolve(
            path,
            headers: OnlineCatalogService.imageRequestHeaders(path),
          )
        : File(path);
    File file;
    try {
      file = await ReaderCropService.crop(source);
    } catch (_) {
      file = source;
    }
    return decode(
      await ui.ImmutableBuffer.fromUint8List(await file.readAsBytes()),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CroppedReaderImage && other.path == path;
  @override
  int get hashCode => Object.hash(path, true);
}

class RepositoryImage extends ImageProvider<RepositoryImage> {
  final String url;
  const RepositoryImage(this.url);
  @override
  Future<RepositoryImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
    RepositoryImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);
  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final file = await ImageRepository.shared.resolve(
      url,
      headers: OnlineCatalogService.imageRequestHeaders(url),
    );
    return decode(
      await ui.ImmutableBuffer.fromUint8List(await file.readAsBytes()),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RepositoryImage && other.url == url;
  @override
  int get hashCode => url.hashCode;
}

ImageProvider boundedImage(
  String path, {
  int width = 1080,
  int height = 8192,
  bool original = false,
  bool cropWhite = false,
}) {
  final ImageProvider provider = cropWhite
      ? CroppedReaderImage(path)
      : path.startsWith('https://') || path.startsWith('http://')
      ? RepositoryImage(path)
      : FileImage(File(path));
  return original
      ? provider
      : ResizeImage(
          provider,
          width: width,
          height: height,
          policy: ResizeImagePolicy.fit,
        );
}
