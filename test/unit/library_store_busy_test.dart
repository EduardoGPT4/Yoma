import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/data/library_store.dart';

void main() {
  const quick = [Duration.zero, Duration.zero, Duration.zero];

  test('una escritura bloqueada se reintenta hasta que entra', () async {
    var calls = 0;
    final result = await LibraryStore.retryBusy(() async {
      calls++;
      if (calls < 3) {
        throw Exception('SqliteException(5): database is locked');
      }
      return 'guardado';
    }, delays: quick);
    expect(result, 'guardado');
    expect(calls, 3);
  });

  test('otros errores no se reintentan', () async {
    var calls = 0;
    await expectLater(
      LibraryStore.retryBusy(() async {
        calls++;
        throw StateError('otro fallo');
      }, delays: quick),
      throwsStateError,
    );
    expect(calls, 1);
  });

  test('si el bloqueo no se libera, al final se informa del error', () async {
    var calls = 0;
    await expectLater(
      LibraryStore.retryBusy(() async {
        calls++;
        throw Exception('database is locked');
      }, delays: quick),
      throwsException,
    );
    expect(calls, quick.length + 1);
  });
}
