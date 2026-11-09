import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yomashi/services/image_repository.dart';

List<int> _jpeg() => [0xff, 0xd8, ...List.filled(16, 0), 0xff, 0xd9];

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('yomashi-paginas-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('migra páginas válidas sin sobrescribir las guardadas', () async {
    final legacy = Directory(p.join(root.path, 'cache', 'yomashi_images'));
    final target = Directory(p.join(root.path, 'support', 'PaginasVistas'));
    await legacy.create(recursive: true);
    await target.create(recursive: true);
    await File(p.join(legacy.path, 'a.image')).writeAsBytes(_jpeg());
    await File(p.join(legacy.path, 'roto.image')).writeAsBytes([1, 2, 3]);
    await File(p.join(legacy.path, 'b.image')).writeAsBytes(_jpeg());
    final kept = File(p.join(target.path, 'b.image'));
    await kept.writeAsBytes([..._jpeg(), 0xff, 0xd9]);
    final before = await kept.readAsBytes();

    final moved = await ImageRepository.migrateLegacyDirectory(legacy, target);

    expect(moved, 1);
    expect(await File(p.join(target.path, 'a.image')).exists(), isTrue);
    expect(await File(p.join(target.path, 'roto.image')).exists(), isFalse);
    expect(await kept.readAsBytes(), before);
    expect(await legacy.exists(), isFalse);
  });

  test('sin caché anterior no crea nada', () async {
    final target = Directory(p.join(root.path, 'PaginasVistas'));
    final legacy = Directory(p.join(root.path, 'no-existe'));

    final moved = await ImageRepository.migrateLegacyDirectory(legacy, target);

    expect(moved, 0);
    expect(await target.exists(), isFalse);
  });
}
