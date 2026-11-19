import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/features/anime/data/local_anime_downloads.dart';

void main() {
  test('un error del sistema se muestra como un mensaje claro', () {
    final text = animeErrorText(
      const SocketException("Failed host lookup: 'tv.yoma.site'"),
    );
    expect(
      text,
      'Sin conexión a internet. Revisa tu red e inténtalo de nuevo.',
    );
    expect(text, isNot(contains('SocketException')));
  });

  test('un mensaje propio se conserva tal cual', () {
    expect(
      animeErrorText(const AnimeSourceFailureCompat('El episodio no existe.')),
      'El episodio no existe.',
    );
  });
}
