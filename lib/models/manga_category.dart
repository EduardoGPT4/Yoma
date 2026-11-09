class MangaCategory {
  final String id;
  final String name;
  final List<String> mangaKeys;

  const MangaCategory({
    required this.id,
    required this.name,
    this.mangaKeys = const <String>[],
  });

  MangaCategory copyWith({String? id, String? name, List<String>? mangaKeys}) {
    return MangaCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      mangaKeys: mangaKeys ?? this.mangaKeys,
    );
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'mangaKeys': mangaKeys};
  }

  factory MangaCategory.fromMap(Map<String, dynamic> map) {
    return MangaCategory(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      mangaKeys:
          (map['mangaKeys'] as List<dynamic>?)?.cast<String>() ?? <String>[],
    );
  }
}
