/// Cálculo de página al abrir un capítulo.
class ReaderPaging {
  static int spreadCount(int pages, {bool coverAlone = false}) => pages <= 0
      ? 0
      : coverAlone
      ? 1 + ((pages - 1) / 2).ceil()
      : (pages / 2).ceil();
  static int spreadForPage(int page, {bool coverAlone = false}) =>
      coverAlone && page > 0
      ? 1 + (page - 1) ~/ 2
      : coverAlone
      ? 0
      : page ~/ 2;
  static int firstPageForSpread(int spread, {bool coverAlone = false}) =>
      coverAlone && spread > 0
      ? 1 + (spread - 1) * 2
      : coverAlone
      ? 0
      : spread * 2;

  /// Página inicial. [initialPage] &lt; 0 = última (capítulo anterior).
  static int startPage({required int initialPage, required int pageCount}) {
    if (pageCount <= 0) {
      return 0;
    }
    if (initialPage < 0) {
      return pageCount - 1;
    }
    if (initialPage >= pageCount) {
      return pageCount - 1;
    }
    return initialPage;
  }
}
