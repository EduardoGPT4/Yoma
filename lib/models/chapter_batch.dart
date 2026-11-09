import 'chapter.dart';

class ChapterBatch {
  final List<Chapter> chapters;
  final int nextCursor;
  final bool hasMore;
  const ChapterBatch({
    required this.chapters,
    required this.nextCursor,
    required this.hasMore,
  });
}
