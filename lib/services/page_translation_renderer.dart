import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../models/page_translation.dart';

/// Raster copies keep text aligned in zoom, double-page and webtoon modes.
/// The source image is never overwritten.
class PageTranslationRenderer {
  static Future<void> prepare(File source, File target) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      await source.readAsBytes(),
    );
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final scale = math.min(
        1.0,
        math.min(
          2048 / descriptor.width,
          math.min(
            16384 / descriptor.height,
            math.sqrt(8000000 / (descriptor.width * descriptor.height)),
          ),
        ),
      );
      final codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()),
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          await _write(frame.image, target);
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  /// Returns the number of blocks available only in the text comparison sheet.
  static Future<int> render(
    File source,
    File target,
    List<TranslationBlock> blocks,
  ) async {
    final codec = await ui.instantiateImageCodec(await source.readAsBytes());
    final frame = await codec.getNextFrame();
    codec.dispose();
    final image = frame.image;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    var textOnly = 0;
    try {
      canvas.drawImage(image, Offset.zero, Paint());
      final page = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      for (final block in blocks) {
        final bounds = block.bounds.inflate(2).intersect(page);
        if (bounds.width < 8 || bounds.height < 8) {
          textOnly++;
          continue;
        }
        final area = bounds.deflate(2);
        final painter = TextPainter(
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        );
        try {
          var size = math.min(40.0, area.height);
          var fits = false;
          while (size >= 8) {
            painter.text = TextSpan(
              text: block.translated,
              style: TextStyle(
                color: const Color(0xff111111),
                fontSize: size,
                height: 1.1,
              ),
            );
            painter.layout(maxWidth: area.width);
            if (painter.height <= area.height &&
                painter.width <= area.width &&
                painter.computeLineMetrics().every(
                  (line) => line.width <= area.width,
                )) {
              fits = true;
              break;
            }
            size -= 1;
          }
          if (!fits) {
            textOnly++;
            continue;
          }
          canvas.drawRect(bounds, Paint()..color = const Color(0xffffffff));
          painter.paint(
            canvas,
            Offset(area.left, area.top + (area.height - painter.height) / 2),
          );
        } finally {
          painter.dispose();
        }
      }
      final picture = recorder.endRecording();
      try {
        final output = await picture.toImage(image.width, image.height);
        try {
          await _write(output, target);
        } finally {
          output.dispose();
        }
      } finally {
        picture.dispose();
      }
      return textOnly;
    } finally {
      if (recorder.isRecording) recorder.endRecording().dispose();
      image.dispose();
    }
  }

  static Future<void> _write(ui.Image image, File target) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('No se pudo preparar la imagen.');
    await target.writeAsBytes(data.buffer.asUint8List(), flush: true);
  }
}
