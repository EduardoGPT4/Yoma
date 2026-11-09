import 'online_manga.dart';

class CatalogPage {
  final List<OnlineMangaSummary> items;
  final int currentPage;
  final int? totalPages;

  const CatalogPage({
    required this.items,
    this.currentPage = 1,
    this.totalPages,
  });

  bool get hasNext =>
      totalPages != null ? currentPage < totalPages! : items.isNotEmpty;
}

typedef TmoCatalogPage = CatalogPage;
