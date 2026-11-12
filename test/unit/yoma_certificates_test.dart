import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/config/yoma_certificates.dart';

String normalize(String pem) => pem.replaceAll('\r', '').trim();

void main() {
  test('Dart y Android llevan los mismos intermedios', () {
    final raw = Directory('android/app/src/main/res/raw')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.pem'))
        .toList();
    expect(raw, hasLength(gtsIntermediates.length));
    for (final entry in gtsIntermediates.entries) {
      final file = File('android/app/src/main/res/raw/gts_${entry.key}.pem');
      expect(
        normalize(file.readAsStringSync()),
        normalize(entry.value),
        reason: entry.key,
      );
    }
  });

  test('la configuración de red de Android los usa para yoma.site', () {
    for (final path in [
      'android/app/src/main/res/xml/network_security_config.xml',
      'android/app/src/debug/res/xml/qa_network_security.xml',
    ]) {
      final xml = File(path).readAsStringSync();
      expect(
        xml,
        contains('<domain includeSubdomains="true">yoma.site</domain>'),
      );
      expect(xml, contains('<certificates src="system"/>'), reason: path);
      for (final name in gtsIntermediates.keys) {
        expect(xml, contains('@raw/gts_$name'), reason: '$path $name');
      }
    }
    expect(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      contains('android:networkSecurityConfig="@xml/network_security_config"'),
    );
  });

  test('son certificados válidos que el cliente acepta', () {
    for (final pem in gtsIntermediates.values) {
      expect(pem.trim(), startsWith('-----BEGIN CERTIFICATE-----'));
      expect(pem.trim(), endsWith('-----END CERTIFICATE-----'));
    }
    final client = yomaHttpClient();
    addTearDown(() => client.close(force: true));
  });
}
