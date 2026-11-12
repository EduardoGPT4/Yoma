import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// La web usa los mismos tokens que la app: el bloque `--yoma-*` de cada hoja
/// lo genera tools/generate_web_tokens.py desde lib/design/yoma_tokens.dart.
const sheets = [
  'web/yoma.site/style.css',
  'web/shi.yoma.site/style.css',
  'web/tv.yoma.site/releases/yoma-design-20261111-1/assets/yoma.css',
];

String kebab(String name) => name
    .replaceAllMapped(RegExp(r'(?<=[a-z0-9])([A-Z])'), (m) => '-${m[1]}')
    .toLowerCase();

Map<String, String> appTokens() {
  final source = File('lib/design/yoma_tokens.dart').readAsStringSync();
  String section(String name) => RegExp(
    'abstract final class $name \\{(.*?)\\n\\}',
    dotAll: true,
  ).firstMatch(source)![1]!;
  return {
    for (final m in RegExp(
      r'static const (\w+) = Color\(0x([0-9A-Fa-f]{8})\);',
    ).allMatches(section('YomaColors')))
      '--yoma-${kebab(m[1]!)}': '#${m[2]!.substring(2).toLowerCase()}',
    for (final m in RegExp(
      r'static const double (\w+) = ([0-9.]+);',
    ).allMatches(section('YomaRadii')))
      '--yoma-radius-${kebab(m[1]!)}':
          '${double.parse(m[2]!).toStringAsFixed(0)}px',
  };
}

/// Declaraciones `--nombre: valor` del primer bloque que empieza por [selector].
Map<String, String> declarations(String css, String selector) {
  final start = css.indexOf(selector);
  expect(start, greaterThanOrEqualTo(0), reason: selector);
  final body = css.substring(
    css.indexOf('{', start) + 1,
    css.indexOf('}', start),
  );
  return {
    for (final m in RegExp(r'(--[\w-]+)\s*:\s*([^;]+);').allMatches(body))
      m[1]!: m[2]!.trim(),
  };
}

void main() {
  final tokens = appTokens();

  test('cada hoja lleva los tokens de la app, con los mismos valores', () {
    expect(tokens['--yoma-background'], '#101014');
    expect(tokens['--yoma-radius-lg'], '16px');
    for (final path in sheets) {
      final css = File(path).readAsStringSync();
      final generated = css.substring(
        css.indexOf('/* yoma-tokens:start'),
        css.indexOf('/* yoma-tokens:end */'),
      );
      expect(declarations(generated, ':root'), tokens, reason: path);
    }
  });

  test(
    'los nombres de cada sitio apuntan a los tokens, no a colores sueltos',
    () {
      String resolve(Map<String, String> values, String name) {
        final value = values[name]!;
        final ref = RegExp(r'^var\((--yoma-[\w-]+)\)$').firstMatch(value);
        expect(ref, isNotNull, reason: '$name = $value');
        return tokens[ref![1]]!;
      }

      for (final path in [
        'web/yoma.site/style.css',
        'web/shi.yoma.site/style.css',
      ]) {
        final css = File(path).readAsStringSync();
        final site = declarations(
          css.substring(css.indexOf('/* yoma-tokens:end */')),
          ':root',
        );
        expect(resolve(site, '--bg'), '#101014', reason: path);
        expect(resolve(site, '--surface'), '#211f27', reason: path);
        expect(resolve(site, '--accent'), '#f0848d', reason: path);
        for (final name in [
          '--surface-low',
          '--surface-high',
          '--border',
          '--text',
          '--text-2',
          '--text-3',
          '--on-accent',
          '--anime',
          '--manga',
          '--radius',
          '--radius-lg',
        ]) {
          resolve(site, name);
        }
      }

      // YomaTV conserva sus nombres de la web; su superficie es la baja de la app.
      final tv = declarations(
        File(
          'web/tv.yoma.site/releases/yoma-design-20261111-1/assets/yoma.css',
        ).readAsStringSync(),
        ':root, :root[data-theme]',
      );
      expect(resolve(tv, '--surface'), tokens['--yoma-surface-low']);
      expect(resolve(tv, '--surface2'), tokens['--yoma-surface']);
      for (final name in [
        '--bg',
        '--line',
        '--line-strong',
        '--text',
        '--muted',
        '--accent',
        '--accent-ink',
        '--gold',
        '--ok',
        '--info',
        '--danger',
        '--yoma-anime',
        '--yoma-manga',
      ]) {
        resolve(tv, name);
      }
    },
  );

  test('yoma.site y shi.yoma.site comparten la misma hoja', () {
    expect(
      File('web/shi.yoma.site/style.css').readAsStringSync(),
      File('web/yoma.site/style.css').readAsStringSync(),
    );
  });
}
