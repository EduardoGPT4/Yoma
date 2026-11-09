import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../models/page_translation.dart';
import 'image_repository.dart';
import 'page_translation_renderer.dart';

class TranslationFailure implements Exception {
  final String message;
  const TranslationFailure(this.message);
  @override
  String toString() => message;
}

class PageTranslationService {
  static const channel = MethodChannel('app.yomashi.reader/translation');
  final ImageRepository images;
  final MethodChannel platform;
  final Map<String, String>? Function(String url)? imageHeaders;
  Future<Directory>? _directory;
  String? _cleanupRoot;
  Future<PageTranslation>? _pending;
  final _cache = <String, PageTranslation>{};
  int _generation = 0;
  String? _requestId;
  Completer<void>? _cancelled;
  bool _disposed = false;

  PageTranslationService({
    ImageRepository? images,
    MethodChannel? platform,
    this.imageHeaders,
  }) : images = images ?? ImageRepository.shared,
       platform = platform ?? channel;

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<PageTranslation> translate({
    required String url,
    required String sourceLanguage,
    required String targetLanguage,
    bool wifiOnly = true,
  }) {
    if (_disposed) throw const TranslationFailure('El lector se cerró.');
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const TranslationFailure(
        'La traducción solo está disponible para páginas online.',
      );
    }
    if (!translationLanguages.containsKey(sourceLanguage) ||
        !translationLanguages.containsKey(targetLanguage) ||
        sourceLanguage == targetLanguage) {
      throw const TranslationFailure('Elige dos idiomas diferentes.');
    }
    if (_pending != null) {
      throw const TranslationFailure(
        'Espera a que termine la traducción actual.',
      );
    }
    final key = '$sourceLanguage|$targetLanguage|$url';
    final cached = _cache.remove(key);
    if (cached != null && File(cached.imagePath).existsSync()) {
      _cache[key] = cached;
      return Future.value(cached);
    }
    final generation = ++_generation;
    final id = '${DateTime.now().microsecondsSinceEpoch}-$generation';
    _requestId = id;
    final cancelled = Completer<void>();
    _cancelled = cancelled;
    final pending = _translate(
      url,
      sourceLanguage,
      targetLanguage,
      wifiOnly,
      key,
      generation,
      id,
      cancelled,
    );
    _pending = pending;
    return pending.whenComplete(() {
      _pending = null;
      if (_requestId == id) _requestId = null;
    });
  }

  void _check(int generation) {
    if (_disposed || generation != _generation) {
      throw const TranslationFailure('Traducción cancelada.');
    }
  }

  Future<PageTranslation> _translate(
    String url,
    String source,
    String target,
    bool wifiOnly,
    String key,
    int generation,
    String id,
    Completer<void> cancelled,
  ) async {
    File? input, output;
    var completed = false;
    try {
      final original = await _cancellable(
        images.resolve(url, headers: imageHeaders?.call(url)),
        cancelled,
      ).timeout(const Duration(seconds: 45));
      _check(generation);
      if (await original.length() > 40 * 1024 * 1024) {
        throw const TranslationFailure(
          'La imagen supera el límite de 40 MB para traducir.',
        );
      }
      final directory = await (_directory ??= _createDirectory());
      _check(generation);
      input = File('${directory.path}/$id.input.png');
      output = File('${directory.path}/$id.translated.png');
      await PageTranslationRenderer.prepare(original, input);
      _check(generation);
      final response = await _cancellable(
        platform.invokeMapMethod<Object?, Object?>('translate', {
          'id': id,
          'path': input.path,
          'source': source,
          'target': target,
          'wifiOnly': wifiOnly,
        }),
        cancelled,
      ).timeout(const Duration(minutes: 3));
      _check(generation);
      final blocks =
          (response?['blocks'] as List?)
              ?.map(
                (value) => TranslationBlock.fromMap(
                  (value as Map).cast<Object?, Object?>(),
                ),
              )
              .toList() ??
          <TranslationBlock>[];
      if (blocks.isEmpty) {
        throw const TranslationFailure(
          'No se detectó texto. Prueba otro idioma de origen o una imagen con mayor resolución.',
        );
      }
      final textOnly = await PageTranslationRenderer.render(
        input,
        output,
        blocks,
      );
      _check(generation);
      final result = PageTranslation(
        url: url,
        sourceLanguage: source,
        targetLanguage: target,
        imagePath: output.path,
        blocks: List.unmodifiable(blocks),
        textOnlyBlocks: textOnly,
      );
      _cache[key] = result;
      var bytes = 0;
      for (final cached in _cache.values) {
        final file = File(cached.imagePath);
        if (await file.exists()) bytes += await file.length();
      }
      while (_cache.length > 1 &&
          (_cache.length > 8 || bytes > 64 * 1024 * 1024)) {
        final evicted = _cache.remove(_cache.keys.first)!;
        final file = File(evicted.imagePath);
        if (await file.exists()) {
          bytes -= await file.length();
          await file.delete();
        }
      }
      _check(generation);
      completed = true;
      return result;
    } on MissingPluginException {
      throw const TranslationFailure(
        'La traducción de imágenes está disponible en Android.',
      );
    } on PlatformException catch (error) {
      throw TranslationFailure(
        error.message ?? 'No se pudo traducir la página.',
      );
    } on TimeoutException {
      unawaited(platform.invokeMethod<void>('cancel', id).catchError((_) {}));
      throw const TranslationFailure(
        'La traducción tardó demasiado. Comprueba la conexión y vuelve a intentarlo.',
      );
    } finally {
      if (input != null && await input.exists()) await input.delete();
      if (!completed && output != null && await output.exists()) {
        await output.delete();
      }
    }
  }

  Future<Directory> _createDirectory() async {
    final parent = Directory(
      '${(await getTemporaryDirectory()).path}/yomashi_translation',
    );
    await parent.create(recursive: true);
    _cleanupRoot = await parent.resolveSymbolicLinks();
    return parent.createTemp('reader-');
  }

  Future<T> _cancellable<T>(Future<T> work, Completer<void> cancelled) =>
      Future.any([
        work,
        cancelled.future.then<T>(
          (_) => throw const TranslationFailure('Traducción cancelada.'),
        ),
      ]);

  void cancel() {
    _generation++;
    if (_cancelled?.isCompleted == false) _cancelled!.complete();
    final id = _requestId;
    if (id != null) {
      unawaited(platform.invokeMethod<void>('cancel', id).catchError((_) {}));
    }
  }

  Future<void> clearModels() async {
    try {
      await platform
          .invokeMethod<void>('clearModels')
          .timeout(const Duration(seconds: 30));
    } on PlatformException catch (error) {
      throw TranslationFailure(
        error.message ?? 'No se pudieron eliminar los modelos.',
      );
    } on TimeoutException {
      throw const TranslationFailure(
        'La eliminación de modelos tardó demasiado. Reintenta en unos segundos.',
      );
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    cancel();
    try {
      await _pending;
    } catch (_) {
      /* A cancelled translation owns its cleanup. */
    }
    _cache.clear();
    final directory = await _directory;
    if (directory != null && await directory.exists()) {
      final actual = await directory.resolveSymbolicLinks();
      final root = _cleanupRoot;
      if (root == null ||
          !p.isWithin(root, actual) ||
          !p.basename(actual).startsWith('reader-')) {
        throw const TranslationFailure(
          'No se pudo verificar la carpeta temporal del traductor.',
        );
      }
      await directory.delete(recursive: true);
    }
  }
}
