import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/services/content_exclusions.dart';

void main() {
  test(
    'one configuration contains the existing and additional restrictions',
    () {
      expect(
        ContentExclusions.tags,
        containsAll([
          'loli',
          'shota',
          'guro',
          'ryona',
          'snuff',
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
      ' GURO ',
      'male:RYONA',
      '-tag:snuff',
      'tag:guro_variant',
      'g_u-r o',
      ' r_Y-O N a ',
      's_n-u f f',
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
        'guro',
        'female:guro',
        'male:guro',
        'ryona',
        'female:ryona',
        'male:ryona',
        'snuff',
        'female:snuff',
        'male:snuff',
      ]),
    );
    for (final tag in ContentExclusions.tags) {
      expect(tokens, containsAll([tag, 'female:$tag', 'male:$tag']));
    }
  });
}
