import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/design/yoma_tokens.dart';

const _kotlinDir = 'android/app/src/main/kotlin/app/yomatv/mobile';

Map<String, int> _kotlinColors() {
  final source = File('$_kotlinDir/YomaColors.kt').readAsStringSync();
  return {
    for (final m in RegExp(
      r'const val (\w+) = 0x([0-9A-Fa-f]{8})\.toInt\(\)',
    ).allMatches(source))
      m.group(1)!: int.parse(m.group(2)!, radix: 16),
  };
}

void main() {
  test('las pantallas Kotlin de YomaTV usan los colores de Yoma', () {
    final kotlin = _kotlinColors();
    final expected = <String, Color>{
      'BACKGROUND': YomaColors.background,
      'SURFACE': YomaColors.surface,
      'SURFACE_HIGH': YomaColors.surfaceHigh,
      'SURFACE_LOW': YomaColors.surfaceLow,
      'ACCENT': YomaColors.accent,
      'ON_ACCENT': YomaColors.onAccent,
      'TEXT_PRIMARY': YomaColors.textPrimary,
      'TEXT_SECONDARY': YomaColors.textSecondary,
      'TEXT_MUTED': YomaColors.textMuted,
      'BORDER': YomaColors.border,
      'BORDER_SUBTLE': YomaColors.borderSubtle,
      'SUCCESS': YomaColors.success,
      'ERROR': YomaColors.error,
      'ANIME_TINT': YomaColors.animeTint,
    };
    for (final entry in expected.entries) {
      expect(kotlin[entry.key], entry.value.toARGB32(), reason: entry.key);
    }
    // El fondo del capítulo actual es el acento al 10 % sobre la superficie.
    final soft = Color.alphaBlend(
      YomaColors.accent.withValues(alpha: .1),
      YomaColors.surface,
    );
    final value = kotlin['ACCENT_SOFT']!;
    for (final (a, b) in [
      ((value >> 16) & 0xff, (soft.r * 255).round()),
      ((value >> 8) & 0xff, (soft.g * 255).round()),
      (value & 0xff, (soft.b * 255).round()),
    ]) {
      expect((a - b).abs(), lessThanOrEqualTo(1));
    }
  });

  test('no quedan colores fijos fuera de YomaColors.kt', () {
    for (final file in Directory(_kotlinDir).listSync().whereType<File>()) {
      if (file.path.endsWith('YomaColors.kt')) continue;
      final source = file.readAsStringSync();
      expect(
        RegExp(r'0x[fF]{2}[0-9a-fA-F]{6}').hasMatch(source),
        isFalse,
        reason: file.path,
      );
      // Los títulos usan la letra de Yoma (YomaType), no una con serifa.
      expect(source, isNot(contains('"serif"')), reason: file.path);
    }
  });

  test('el tema de las actividades nativas usa el fondo y acento de Yoma', () {
    final xml = File(
      'android/app/src/main/res/values/anime_styles.xml',
    ).readAsStringSync();
    String hex(Color c) =>
        '#${(c.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    expect(xml, contains('colorAccent">${hex(YomaColors.accent)}<'));
    for (final item in [
      'windowBackground',
      'navigationBarColor',
      'statusBarColor',
    ]) {
      expect(xml, contains('$item">${hex(YomaColors.background)}<'));
    }
  });
}
