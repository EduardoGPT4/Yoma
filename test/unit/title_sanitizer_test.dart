import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/utils/title_sanitizer.dart';

void main() {
  group('textos de buscador en el título', () {
    test('se quitan los de las fichas de TuMangaOnline', () {
      const cases = {
        'Ver BLACK MOOON Online Gratis': 'BLACK MOOON',
        'Ver Shougakusei ga Mama demo Ii desu ka? Online Gratis':
            'Shougakusei ga Mama demo Ii desu ka?',
        'Ver No Toques Al Sacerdote Puro Online Gratis':
            'No Toques Al Sacerdote Puro',
        'Leer One Piece Manga Online Gratis en Español': 'One Piece',
        'Leer Solo Leveling online': 'Solo Leveling',
        'Dandadan - Leer Manga Online Gratis': 'Dandadan',
        'Kagurabachi Manga Online': 'Kagurabachi',
        'Frieren Online Gratis': 'Frieren',
        'Blue Lock gratis en español': 'Blue Lock',
      };
      cases.forEach(
        (raw, clean) => expect(TitleSanitizer.clean(raw), clean, reason: raw),
      );
    });

    test('se respetan los títulos que llevan esas palabras', () {
      for (final title in [
        'Sword Art Online',
        'Ver y no tocar',
        'Leer entre líneas',
        'Online Game Master',
        'Gratis',
      ]) {
        expect(TitleSanitizer.clean(title), title);
      }
      expect(
        TitleSanitizer.clean('Ver Sword Art Online Online Gratis'),
        'Sword Art Online',
      );
    });
  });

  group('paréntesis y corchetes', () {
    test('se conservan los que forman parte del título', () {
      expect(
        TitleSanitizer.clean('Choujin X (Reedición)'),
        'Choujin X (Reedición)',
      );
      expect(TitleSanitizer.clean('[Oshi no Ko]'), '[Oshi no Ko]');
      expect(
        TitleSanitizer.clean('Ore wa Subete o [Parry] Suru'),
        'Ore wa Subete o [Parry] Suru',
      );
    });

    test('se quitan los sueltos que dejan los metadatos', () {
      expect(
        TitleSanitizer.clean('One Piece [Traducción: Equipo]'),
        'One Piece',
      );
      expect(TitleSanitizer.clean('(Berserk'), 'Berserk');
      expect(TitleSanitizer.clean('Berserk)'), 'Berserk');
      expect(TitleSanitizer.clean('Naruto - 12'), 'Naruto');
    });
  });
}
