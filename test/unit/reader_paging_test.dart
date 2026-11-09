import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/utils/reader_paging.dart';

void main() {
  test('a separate cover keeps every page in exactly one spread', () {
    expect(ReaderPaging.spreadCount(7, coverAlone: true), 4);
    expect(
      [
        for (var i = 0; i < 4; i++)
          ReaderPaging.firstPageForSpread(i, coverAlone: true),
      ],
      [0, 1, 3, 5],
    );
    expect(
      [
        for (var i = 0; i < 7; i++)
          ReaderPaging.spreadForPage(i, coverAlone: true),
      ],
      [0, 1, 1, 2, 2, 3, 3],
    );
  });
  group('ReaderPaging.startPage', () {
    test('next chapter always opens page 1 (index 0)', () {
      expect(ReaderPaging.startPage(initialPage: 0, pageCount: 24), 0);
    });

    test('previous chapter with initialPage < 0 opens the last page', () {
      expect(ReaderPaging.startPage(initialPage: -1, pageCount: 18), 17);
    });

    test('resume mid-chapter stays on the saved page', () {
      expect(ReaderPaging.startPage(initialPage: 7, pageCount: 20), 7);
    });

    test('empty chapter stays at 0', () {
      expect(ReaderPaging.startPage(initialPage: 5, pageCount: 0), 0);
    });
  });
}
