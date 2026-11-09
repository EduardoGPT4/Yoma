class FavoriteEntry {
  final String key;
  final String title;
  final String? coverPath;

  const FavoriteEntry({required this.key, required this.title, this.coverPath});

  Map<String, dynamic> toMap() {
    return {'key': key, 'title': title, 'coverPath': coverPath};
  }

  factory FavoriteEntry.fromMap(Map<String, dynamic> map) {
    return FavoriteEntry(
      key: map['key'] as String? ?? '',
      title: map['title'] as String? ?? '',
      coverPath: map['coverPath'] as String?,
    );
  }
}
