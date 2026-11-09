import '../models/catalog_page.dart';
import '../models/chapter_batch.dart';
import '../models/online_manga.dart';

class SourceCapabilities {
  final String feedLabel;
  final bool typeFilter;
  final bool statusFilter;
  const SourceCapabilities({
    this.feedLabel = 'Actualizados',
    this.typeFilter = true,
    this.statusFilter = true,
  });
}

abstract class MangaSourceAdapter {
  String get id;
  SourceCapabilities get capabilities;
  Future<CatalogPage> catalog({int page = 1, int pageSize = 12, String? query});
  Future<List<OnlineMangaSummary>> feed();
  Future<OnlineMangaDetail> detail(String ref);
  Future<List<String>> pages(String ref);
  Future<ChapterBatch> chapterBatch(String ref, int cursor);
}

class CallbackSourceAdapter implements MangaSourceAdapter {
  @override
  final String id;
  @override
  final SourceCapabilities capabilities;
  final Future<CatalogPage> Function(int, int, String?) catalogRequest;
  final Future<List<OnlineMangaSummary>> Function() feedRequest;
  final Future<OnlineMangaDetail> Function(String) detailRequest;
  final Future<List<String>> Function(String) pagesRequest;
  final Future<ChapterBatch> Function(String, int)? chapterRequest;
  CallbackSourceAdapter({
    required this.id,
    required this.catalogRequest,
    required this.feedRequest,
    required this.detailRequest,
    required this.pagesRequest,
    this.chapterRequest,
    this.capabilities = const SourceCapabilities(),
  });
  @override
  Future<CatalogPage> catalog({
    int page = 1,
    int pageSize = 12,
    String? query,
  }) => catalogRequest(page, pageSize, query);
  @override
  Future<List<OnlineMangaSummary>> feed() => feedRequest();
  @override
  Future<OnlineMangaDetail> detail(String ref) => detailRequest(ref);
  @override
  Future<List<String>> pages(String ref) => pagesRequest(ref);
  @override
  Future<ChapterBatch> chapterBatch(String ref, int cursor) {
    final request = chapterRequest;
    if (request == null) throw StateError('Esta fuente no pagina capítulos.');
    return request(ref, cursor);
  }
}
