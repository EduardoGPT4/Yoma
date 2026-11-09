import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/services/hitomi_service.dart';

void main() {
  test('exclusion filter recognizes blocked tags after normalization', () {
    expect(HitomiService.blockedTagNames, isNotEmpty);
    expect(HitomiService.tagIsBlocked('  LOLI  '), isTrue);
    expect(HitomiService.tagIsBlocked('ShOtA'), isTrue);
    expect(HitomiService.tagIsBlocked('adventure'), isFalse);
    expect(HitomiService.tagIsBlocked(''), isFalse);
  });

  test('exclusion filter rejects blocked metadata among unrelated tags', () {
    expect(
      HitomiService.galleryIsBlocked({
        'tags': [
          {'tag': 'adventure'},
          {'tag': 'LOLI'},
        ],
      }),
      isTrue,
    );
    expect(
      HitomiService.galleryIsBlocked({
        'tags': [
          {'tag': 'adventure'},
        ],
      }),
      isFalse,
    );
    expect(HitomiService.galleryIsBlocked({}), isFalse);
  });

  test('additional restrictions apply to metadata and suggestions', () {
    for (final tag in ['guro', 'ryona', 'snuff']) {
      expect(HitomiService.tagIsBlocked(' ${tag.toUpperCase()} '), isTrue);
      expect(HitomiService.suggestionAllowed('tag', tag), isFalse);
      expect(
        HitomiService.galleryIsBlocked({
          'tags': [
            {'tag': 'adventure'},
            {'tag': tag},
          ],
        }),
        isTrue,
      );
    }
  });
}
