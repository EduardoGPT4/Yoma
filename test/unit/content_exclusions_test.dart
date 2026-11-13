import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/services/content_exclusions.dart';

void main() {
  test(
    'one configuration contains the existing rules and minor protection',
    () {
      expect(
        ContentExclusions.tags,
        containsAll([
          'loli',
          'shota',
          'electroencefalografista',
          'esternocleidomastoideo',
        ]),
      );
      for (final tag in ContentExclusions.tags) {
        expect(tag, isNotEmpty);
        expect(tag, tag.trim().toLowerCase());
        expect(ContentExclusions.matches(tag), isTrue, reason: tag);
      }
    },
  );

  test('recognizes case, separators, compound tags and query namespaces', () {
    for (final value in [
      ' LOLI ',
      'male:SHOTA',
      '-tag:loli',
      'tag:shota_variant',
      'l_o-l i',
      ' s_H-O T a ',
    ]) {
      expect(ContentExclusions.matches(value), isTrue, reason: value);
    }
    for (final value in ['', 'adventure', 'artist:autor', 'type:manga']) {
      expect(ContentExclusions.matches(value), isFalse, reason: value);
    }
  });

  test('the same rules supply general and namespaced exclusion indexes', () {
    final tokens = ContentExclusions.indexTokens.toSet();
    expect(
      tokens,
      containsAll([
        'loli',
        'female:loli',
        'male:loli',
        'shota',
        'female:shota',
        'male:shota',
      ]),
    );
    for (final tag in ContentExclusions.tags) {
      expect(tokens, containsAll([tag, 'female:$tag', 'male:$tag']));
    }
  });
}
