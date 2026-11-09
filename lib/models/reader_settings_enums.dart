enum ReadingDirection {
  leftToRight,
  rightToLeft,
  vertical;

  String get label {
    switch (this) {
      case ReadingDirection.leftToRight:
        return 'Izquierda → Derecha';
      case ReadingDirection.rightToLeft:
        return 'Derecha → Izquierda';
      case ReadingDirection.vertical:
        return 'Vertical';
    }
  }

  String get shortLabel {
    switch (this) {
      case ReadingDirection.leftToRight:
        return 'LTR';
      case ReadingDirection.rightToLeft:
        return 'RTL';
      case ReadingDirection.vertical:
        return 'Vertical';
    }
  }
}

enum PageFitMode {
  fitWidth,
  fitHeight,
  original;

  String get label {
    switch (this) {
      case PageFitMode.fitWidth:
        return 'Ajustar a ancho';
      case PageFitMode.fitHeight:
        return 'Ajustar a alto';
      case PageFitMode.original:
        return 'Original';
    }
  }
}

enum PageTransitionSpeed {
  none,
  fast,
  normal,
  slow;

  String get label {
    switch (this) {
      case PageTransitionSpeed.none:
        return 'Instantanea';
      case PageTransitionSpeed.fast:
        return 'Rapida';
      case PageTransitionSpeed.normal:
        return 'Normal';
      case PageTransitionSpeed.slow:
        return 'Lenta';
    }
  }

  Duration get duration {
    switch (this) {
      case PageTransitionSpeed.none:
        return Duration.zero;
      case PageTransitionSpeed.fast:
        return const Duration(milliseconds: 150);
      case PageTransitionSpeed.normal:
        return const Duration(milliseconds: 300);
      case PageTransitionSpeed.slow:
        return const Duration(milliseconds: 500);
    }
  }
}
