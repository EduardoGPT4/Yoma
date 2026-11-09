import 'dart:io';
import 'package:flutter/material.dart';
import '../services/image_repository.dart';
import '../services/online_catalog_service.dart';
import '../utils/thumbnail_service.dart';

class CachedThumbnail extends StatefulWidget {
  final String? sourcePath;
  final BoxFit fit;
  final int size;
  final Widget Function(BuildContext) placeholderBuilder;
  const CachedThumbnail({
    super.key,
    required this.sourcePath,
    required this.placeholderBuilder,
    this.fit = BoxFit.cover,
    this.size = 360,
  });
  @override
  State<CachedThumbnail> createState() => _CachedThumbnailState();
}

class _CachedThumbnailState extends State<CachedThumbnail> {
  Future<File?>? _file;
  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(CachedThumbnail old) {
    super.didUpdateWidget(old);
    if (old.sourcePath != widget.sourcePath || old.size != widget.size) {
      _resolve();
    }
  }

  void _resolve() {
    final source = widget.sourcePath;
    _file = source == null || source.isEmpty
        ? Future.value(null)
        : source.startsWith('http')
        ? ImageRepository.shared.resolve(
            source,
            headers: OnlineCatalogService.imageRequestHeaders(source),
          )
        : ThumbnailService.getThumbnail(source, size: widget.size);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<File?>(
    future: _file,
    builder: (context, snapshot) {
      final file = snapshot.data;
      return file == null
          ? widget.placeholderBuilder(context)
          : Image.file(
              file,
              fit: widget.fit,
              cacheWidth: widget.size,
              errorBuilder: (_, _, _) => widget.placeholderBuilder(context),
            );
    },
  );
}
