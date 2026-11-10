import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../design/yoma_tokens.dart';

/// Animación de entrada del selector de Yoma: la interfaz parece programarse
/// y construirse en tiempo real (≈3 s). Todo es decoración sin interacción:
/// las capas ignoran los toques y, al terminar, el selector se dibuja sin
/// ninguna de ellas.
class SelectorIntro {
  static const duration = Duration(milliseconds: 3200);
  static const _seconds = 3.2;

  /// Momento en que empieza a construirse cada tarjeta.
  static const mangaStart = 1.05, animeStart = 1.55, malStart = 2.25;

  final double t;
  const SelectorIntro(double value) : t = value * _seconds;

  bool get done => t >= _seconds;

  /// Progreso 0–1 entre [start] y [end] (segundos).
  double at(double start, double end, [Curve curve = Curves.linear]) =>
      curve.transform(((t - start) / (end - start)).clamp(0.0, 1.0));

  /// Sube y baja: aparece, se mantiene y se desvanece dentro del tramo.
  double pulse(double start, double end, {double hold = .5}) {
    final p = at(start, end);
    if (p <= 0 || p >= 1) return 0;
    final rise = (1 - hold) / 2;
    if (p < rise) return p / rise;
    if (p > 1 - rise) return (1 - p) / rise;
    return 1;
  }

  /// Cursor de escritura que parpadea.
  bool get caretOn => (t * 7).floor().isEven;

  CardIntro card(double start) => CardIntro(this, start);
}

/// Fases de una tarjeta: se dibuja (código y borde) y luego se resuelve en el
/// componente real.
class CardIntro {
  final SelectorIntro intro;
  final double start;
  const CardIntro(this.intro, this.start);

  double get resolveAt => start + .55;
  double get border => intro.at(start, start + .45);
  double get markers =>
      intro.at(start, start + .12) * (1 - intro.at(resolveAt, resolveAt + .2));
  double get typing => intro.at(start + .05, start + .5);
  double get codeExit => intro.at(resolveAt, resolveAt + .22);
  double get building => 1 - intro.at(resolveAt, resolveAt + .3);
  double get compile => intro.at(resolveAt, resolveAt + .32, Curves.easeOut);
  double get shine => intro.at(resolveAt + .4, resolveAt + .85);
  double get fill => intro.at(resolveAt, resolveAt + .37, Curves.easeOutCubic);
  double get thumb =>
      intro.at(resolveAt + .06, resolveAt + .41, Curves.easeOut);
  double get brand => intro.at(resolveAt + .12, resolveAt + .38);
  double get title => intro.at(resolveAt + .18, resolveAt + .44);
  double get detail => intro.at(resolveAt + .25, resolveAt + .51);
  double get icon =>
      intro.at(resolveAt + .3, resolveAt + .66, Curves.easeOutBack);
  double get annotation => intro.pulse(start - .05, start + .65);
}

/// Un fragmento de código con su color.
typedef CodeSpan = (String text, Color color);

const _mono = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: ['Roboto Mono', 'Courier New'],
  fontFeatures: [ui.FontFeature.tabularFigures()],
);

/// Código que se escribe carácter a carácter con resaltado de sintaxis.
class TypedCode extends StatelessWidget {
  final List<CodeSpan> spans;
  final double progress;
  final bool caret;
  final double fontSize;

  const TypedCode({
    super.key,
    required this.spans,
    required this.progress,
    required this.caret,
    this.fontSize = 12,
  });

  /// `<Nombre atributo="valor" />` con colores de etiqueta, nombre y texto.
  static List<CodeSpan> tag(String name, String attribute, String value) => [
    ('<', YomaColors.textSecondary),
    (name, YomaColors.success),
    (' $attribute', YomaColors.mangaTint),
    ('=', YomaColors.textSecondary),
    ('"$value"', YomaColors.animeTint),
    (' />', YomaColors.textSecondary),
  ];

  @override
  Widget build(BuildContext context) {
    final total = spans.fold<int>(0, (n, s) => n + s.$1.length);
    var left = (total * progress).round();
    final children = <InlineSpan>[];
    for (final (text, color) in spans) {
      if (left <= 0) break;
      final part = text.substring(0, math.min(left, text.length));
      left -= part.length;
      children.add(
        TextSpan(
          text: part,
          style: TextStyle(color: color),
        ),
      );
    }
    // Cursor dibujado: no depende de que la fuente tenga el carácter.
    children.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _Caret(visible: caret, height: fontSize * 1.15),
      ),
    );
    return Text.rich(
      TextSpan(children: children),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.clip,
      style: _mono.copyWith(
        fontSize: fontSize,
        height: 1.6,
        shadows: [
          Shadow(color: YomaColors.mangaTint.withAlpha(110), blurRadius: 12),
        ],
      ),
    );
  }
}

/// Matriz de saturación (0 = gris, 1 = color original).
ColorFilter saturation(double value) {
  final s = value.clamp(0.0, 1.0);
  const r = .2126, g = .7152, b = .0722;
  final i = 1 - s;
  return ColorFilter.matrix([
    r * i + s, g * i, b * i, 0, 0, //
    r * i, g * i + s, b * i, 0, 0, //
    r * i, g * i, b * i + s, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);
}

/// Rectángulo redondeado que se traza progresivamente con un brillo suave.
class TracePainter extends CustomPainter {
  final double progress;
  final double radius;
  final Color color;
  final double opacity;

  const TracePainter({
    required this.progress,
    required this.radius,
    required this.color,
    this.opacity = 1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || opacity <= 0) return;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(.75),
      );
    for (final metric in path.computeMetrics()) {
      final drawn = metric.extractPath(0, metric.length * progress);
      canvas.drawPath(
        drawn,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = color.withValues(alpha: .35 * opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawPath(
        drawn,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = color.withValues(alpha: opacity),
      );
      // Chispa en la punta del trazo.
      if (progress < 1) {
        final tip = metric.getTangentForOffset(metric.length * progress);
        if (tip != null) {
          canvas.drawCircle(
            tip.position,
            3,
            Paint()
              ..color = Colors.white.withValues(alpha: .8 * opacity)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(TracePainter old) =>
      old.progress != progress || old.opacity != opacity || old.color != color;
}

/// Esquinas de selección (arriba a la izquierda y abajo a la derecha).
class _MarkerPainter extends CustomPainter {
  final Color color;
  final double opacity;
  const _MarkerPainter(this.color, this.opacity);

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = color.withValues(alpha: opacity);
    const l = 15.0;
    canvas.drawPath(
      Path()
        ..moveTo(0, l)
        ..lineTo(0, 0)
        ..lineTo(l, 0),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width - l, size.height)
        ..lineTo(size.width, size.height)
        ..lineTo(size.width, size.height - l),
      paint,
    );
  }

  @override
  bool shouldRepaint(_MarkerPainter old) =>
      old.opacity != opacity || old.color != color;
}

/// Capa sobre una tarjeta: borde trazándose, esquinas, código que se escribe
/// y se disuelve, línea de compilación y destello final.
class CardBuildOverlay extends StatelessWidget {
  final CardIntro phase;
  final Color accent;
  final List<CodeSpan> code;
  final String annotation;
  final double radius;

  const CardBuildOverlay({
    super.key,
    required this.phase,
    required this.accent,
    required this.code,
    required this.annotation,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final exit = phase.codeExit;
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: TracePainter(
              progress: phase.border,
              radius: radius,
              color: accent,
              opacity: phase.building,
            ),
          ),
          CustomPaint(painter: _MarkerPainter(accent, phase.markers)),
          if (exit < 1 && phase.typing > 0)
            Center(
              child: Opacity(
                opacity: 1 - exit,
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: 4 * exit,
                    sigmaY: 4 * exit,
                  ),
                  child: Transform.scale(
                    scale: 1 + .04 * exit,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: TypedCode(
                          spans: code,
                          progress: phase.typing,
                          caret: phase.intro.caretOn,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (phase.compile > 0 && phase.compile < 1)
            ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: LayoutBuilder(
                builder: (context, box) => Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: -40 + (box.maxHeight + 40) * phase.compile,
                      height: 40,
                      child: Opacity(
                        opacity: .45 * (1 - phase.compile),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [accent.withAlpha(0), accent],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (phase.shine > 0 && phase.shine < 1)
            ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: LayoutBuilder(
                builder: (context, box) => Stack(
                  children: [
                    Positioned(
                      top: -30,
                      bottom: -30,
                      width: 48,
                      left: -80 + (box.maxWidth + 160) * phase.shine,
                      child: Transform(
                        transform: Matrix4.skewX(-.42),
                        child: Opacity(
                          opacity: .3 * math.sin(math.pi * phase.shine),
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Color(0x00FFFFFF),
                                  Color(0x99FFFFFF),
                                  Color(0x00FFFFFF),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (phase.annotation > 0)
            Positioned(
              left: 4,
              top: -20 - 6 * (1 - phase.annotation),
              child: Opacity(
                opacity: .85 * phase.annotation,
                child: Text(
                  annotation,
                  style: _mono.copyWith(
                    fontSize: 10,
                    color: accent.withAlpha(220),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Muestra [child] con desplazamiento y opacidad según [value] (0 → 1).
Widget introReveal(
  double value,
  Widget child, {
  double dx = 0,
  double dy = 0,
  double scaleFrom = 1,
}) {
  if (value >= 1) return child;
  return Opacity(
    opacity: value.clamp(0.0, 1.0),
    child: Transform.translate(
      offset: Offset(dx * (1 - value), dy * (1 - value)),
      child: scaleFrom == 1
          ? child
          : Transform.scale(
              scale: scaleFrom + (1 - scaleFrom) * value,
              child: child,
            ),
    ),
  );
}

/// Imagen que pasa de gris a color mientras aparece.
Widget introColorize(double value, Widget child) => value >= 1
    ? child
    : ColorFiltered(colorFilter: saturation(value), child: child);

/// Texto que se escribe de izquierda a derecha con cursor, sin mover el
/// diseño: el texto completo ocupa su sitio desde el principio.
class TypedReveal extends StatelessWidget {
  final double progress;
  final bool caret;
  final Widget child;
  final int steps;

  const TypedReveal({
    super.key,
    required this.progress,
    required this.caret,
    required this.child,
    this.steps = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (progress >= 1 && !caret) return child;
    final p = steps > 0 ? (progress * steps).ceil() / steps : progress;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            colors: const [Colors.white, Colors.white, Colors.transparent],
            stops: [0, p.clamp(0.0, 1.0), p.clamp(0.0, 1.0)],
          ).createShader(rect),
          child: child,
        ),
        if (caret)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, box) => Stack(
                children: [
                  Positioned(
                    left: box.maxWidth * p.clamp(0.0, 1.0),
                    top: box.maxHeight * .15,
                    bottom: box.maxHeight * .15,
                    width: 2.5,
                    child: const ColoredBox(color: YomaColors.mangaTint),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Capas de toda la pantalla: terminal superior, línea de escaneo, textura
/// de líneas y el resplandor final de «listo».
class IntroScreenOverlay extends StatelessWidget {
  final SelectorIntro intro;
  const IntroScreenOverlay({super.key, required this.intro});

  (String, String) get _step {
    final t = intro.t;
    if (t < .55) return ('> yoma.init()', 'compilando...');
    if (t < SelectorIntro.mangaStart) return ('> render(Logo)', '01 / 04');
    if (t < SelectorIntro.animeStart) return ('> mount(YomaShi)', '02 / 04');
    if (t < SelectorIntro.malStart) return ('> mount(YomaTV)', '03 / 04');
    if (t < 2.85) return ('> connect(MAL)', '04 / 04');
    return ('> build complete', 'LISTO');
  }

  double get _stepStart {
    final t = intro.t;
    for (final start in [2.85, 2.25, 1.55, 1.05, .55]) {
      if (t >= start) return start;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final fade = 1 - intro.at(2.95, 3.2);
    final (prompt, status) = _step;
    final typed = intro.at(_stepStart, _stepStart + .22);
    final sweep = intro.at(.1, 2.9, Curves.easeInOut);
    final glow = intro.pulse(2.85, 3.2, hold: 0);
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          children: [
            // Textura de líneas de escaneo, muy tenue.
            Positioned.fill(
              child: Opacity(
                opacity: .5 * fade,
                child: const CustomPaint(painter: _ScanlinesPainter()),
              ),
            ),
            if (sweep > 0 && sweep < 1)
              Positioned(
                left: 0,
                right: 0,
                top: -30 + (box.maxHeight + 30) * sweep,
                height: 2,
                child: Opacity(
                  opacity: .7 * math.sin(math.pi * sweep).clamp(0.0, 1.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Colors.transparent,
                          YomaColors.mangaTint,
                          Colors.transparent,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: YomaColors.mangaTint.withAlpha(150),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (glow > 0)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: YomaColors.mangaTint.withValues(alpha: .7 * glow),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 10,
              left: 16,
              right: 16,
              child: Opacity(
                opacity: intro.at(0, .15) * fade,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        prompt.substring(
                          0,
                          (prompt.length * typed).round().clamp(
                            2,
                            prompt.length,
                          ),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: _mono.copyWith(
                          fontSize: 11,
                          color: YomaColors.textSecondary,
                        ),
                      ),
                    ),
                    _Caret(
                      visible: intro.caretOn && intro.t < 2.85,
                      height: 12,
                    ),
                    const Spacer(),
                    if (intro.t >= 2.85)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.check_rounded,
                          size: 13,
                          color: YomaColors.success,
                        ),
                      ),
                    Text(
                      status,
                      style: _mono.copyWith(
                        fontSize: 11,
                        color: YomaColors.success,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanlinesPainter extends CustomPainter {
  const _ScanlinesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = YomaColors.scrim.withAlpha(40);
    for (var y = 0.0; y < size.height; y += 6) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanlinesPainter old) => false;
}

/// Cursor de bloque fino que parpadea.
class _Caret extends StatelessWidget {
  final bool visible;
  final double height;
  const _Caret({required this.visible, required this.height});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 1),
    child: SizedBox(
      width: height * .5,
      height: height,
      child: ColoredBox(
        color: visible ? YomaColors.mangaTint : Colors.transparent,
      ),
    ),
  );
}
