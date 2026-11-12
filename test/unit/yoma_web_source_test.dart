import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// El código de tv.yoma.site está en web/tv.yoma.site: sin credenciales ni
/// datos generados por el servidor, y con la versión publicada completa.
void main() {
  test('la web del repositorio no lleva credenciales', () {
    final local = Directory('web')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.local.php'))
        .map((f) => f.path)
        .toList();
    expect(local, isEmpty);
    // La configuración real se lee de config.local.php, que solo está en el servidor.
    expect(
      File('web/tv.yoma.site/private/config.example.php').existsSync(),
      isTrue,
    );
  });

  test('la versión publicada coincide con sus huellas', () {
    final current =
        jsonDecode(
              File('web/tv.yoma.site/private/current.json').readAsStringSync(),
            )
            as Map;
    final release = 'web/tv.yoma.site/releases/${current['release']}';
    final ready =
        jsonDecode(File('$release/private/ready.json').readAsStringSync())
            as Map;
    var checked = 0;
    for (final MapEntry(key: name as String, value: hash)
        in (ready['files'] as Map).entries) {
      // Los datos los genera el servidor y las credenciales solo están en
      // él: ninguno se versiona.
      if (const {
            'data',
            'downloads',
            'feeds',
          }.contains(name.split('/').first) ||
          name.endsWith('.local.php')) {
        continue;
      }
      final file = File('$release/$name');
      expect(file.existsSync(), isTrue, reason: name);
      expect(
        sha256.convert(file.readAsBytesSync()).toString(),
        hash,
        reason: name,
      );
      checked++;
    }
    expect(checked, greaterThan(100));
  });

  test('la web usa la misma sincronización que el puente de MAL', () {
    final release = 'web/tv.yoma.site/releases/yoma-design-20261111-1/private';
    for (final name in ['yoma-sync.php', 'yoma-sync-web.php']) {
      expect(
        File('$release/$name').readAsStringSync(),
        File('server/private/$name').readAsStringSync(),
        reason: '$name: la copia de la web debe ser la de server/',
      );
    }
    final app = File('$release/app.php').readAsStringSync();
    expect(app, contains("require_once __DIR__ . '/yoma-sync-web.php';"));
    // Un fallo de la sincronización nunca impide cargar la web.
    expect(
      RegExp(
        r'try \{\s*yoma_sync_web\(\$db, uid\(\)\);\s*\} catch \(Throwable',
      ).hasMatch(app),
      isTrue,
    );
    // MySQL confirma la transacción en curso con CREATE TABLE: las tablas
    // se crean antes de abrirla, nunca dentro de yoma_sync_dispatch.
    final bridge = File('server/private/yomashi-mal.php').readAsStringSync();
    expect(
      bridge.indexOf('yoma_sync_schema(\$db)'),
      lessThan(bridge.indexOf('\$db->beginTransaction();')),
    );
    final sync = File('server/private/yoma-sync.php').readAsStringSync();
    final dispatch = sync.substring(
      sync.indexOf('function yoma_sync_dispatch'),
    );
    expect(dispatch, isNot(contains(r'yoma_sync_schema($db)')));
  });
}
