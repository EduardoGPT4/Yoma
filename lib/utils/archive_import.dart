import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import '../data/download_storage.dart';
import 'app_failure.dart';
import 'sorting.dart';

class ArchiveImport {
  static const imageExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.gif'};
  static Future<Directory> importCbzOrZip({
    required File archiveFile,
    required String destinationRoot,
    String? titleOverride,
    void Function(double)? onProgress,
    CancellationToken? cancellation,
  }) async {
    cancellation?.check();
    final ext = p.extension(archiveFile.path).toLowerCase();
    if (!['.zip', '.cbz'].contains(ext)) {
      throw StateError('Usa un archivo CBZ o ZIP.');
    }
    final root = Directory(p.absolute(destinationRoot));
    await root.create(recursive: true);
    final stage = await root.createTemp('.yomashi-import-');
    final messages = ReceivePort();
    final completed = Completer<void>(), exited = Completer<void>();
    // Registrar el consumidor antes de arrancar el isolate evita errores huérfanos.
    final finish = completed.future;
    unawaited(finish.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
    final subscription = messages.listen((dynamic message) {
      if (message == null) {
        if (!exited.isCompleted) exited.complete();
        if (!completed.isCompleted) {
          completed.completeError(
            StateError('La importación terminó inesperadamente.'),
          );
        }
      } else if (message is double) {
        onProgress?.call(message);
      } else if (message == 'done') {
        if (!completed.isCompleted) completed.complete();
      } else if (!completed.isCompleted) {
        completed.completeError(StateError(message.toString()));
      }
    });
    Isolate? isolate;
    void Function()? removeCancel;
    try {
      isolate = await Isolate.spawn(
        _extract,
        {
          'input': archiveFile.path,
          'output': stage.path,
          'port': messages.sendPort,
        },
        onExit: messages.sendPort,
        onError: messages.sendPort,
        errorsAreFatal: true,
      );
      removeCancel = cancellation?.onCancel(() {
        isolate?.kill(priority: Isolate.immediate);
        if (!completed.isCompleted) {
          completed.completeError(
            const AppFailure(FailureKind.cancelled, 'Importación cancelada.'),
          );
        }
      });
      await finish;
      await exited.future;
      cancellation?.check();
      final title = DownloadStorage.safeName(
        titleOverride ?? p.basenameWithoutExtension(archiveFile.path),
      );
      var target = Directory(p.join(root.path, title));
      var suffix = 1;
      while (await target.exists()) {
        target = Directory(p.join(root.path, '$title (importado $suffix)'));
        suffix++;
      }
      if (!p.isWithin(root.path, target.path)) {
        throw StateError('Destino de importación inválido.');
      }
      return await stage.rename(target.path);
    } finally {
      removeCancel?.call();
      if (isolate != null) {
        isolate.kill(priority: Isolate.immediate);
        await exited.future;
      }
      await subscription.cancel();
      messages.close();
      if (p.isWithin(root.path, stage.path) && await stage.exists()) {
        await stage.delete(recursive: true);
      }
    }
  }

  static void _extract(Map<String, dynamic> args) {
    final port = args['port'] as SendPort;
    InputFileStream? input;
    try {
      input = InputFileStream(args['input'] as String);
      if (input.length > 512 * 1024 * 1024) {
        throw StateError('El archivo supera 512 MiB comprimidos.');
      }
      final archive = ZipDecoder().decodeStream(input, verify: true);
      final images =
          archive.files
              .where(
                (e) =>
                    e.isFile &&
                    imageExtensions.contains(p.extension(e.name).toLowerCase()),
              )
              .toList()
            ..sort((a, b) => naturalCompare(a.name, b.name));
      if (images.isEmpty) {
        throw StateError('El archivo no contiene imágenes compatibles.');
      }
      if (images.length > 10000 ||
          images.fold<int>(0, (n, e) => n + e.size) > 2 * 1024 * 1024 * 1024) {
        throw StateError(
          'La importación supera el límite de 10.000 páginas o 2 GiB.',
        );
      }
      final chapter = Directory(
        p.join(args['output'] as String, 'Capitulo 001'),
      )..createSync(recursive: true);
      for (var i = 0; i < images.length; i++) {
        final file = images[i];
        if (file.size > 128 * 1024 * 1024) {
          throw StateError('Una imagen supera 128 MiB.');
        }
        final out = OutputFileStream(
          p.join(
            chapter.path,
            (i + 1).toString().padLeft(5, '0') +
                p.extension(file.name).toLowerCase(),
          ),
        );
        try {
          file.writeContent(out);
        } finally {
          out.closeSync();
        }
        port.send((i + 1) / images.length);
      }
      archive.clear();
      port.send('done');
    } catch (error) {
      port.send(error.toString());
    } finally {
      input?.closeSync();
    }
  }
}
