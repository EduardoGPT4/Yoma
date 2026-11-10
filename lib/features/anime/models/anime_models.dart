import '../../../utils/title_sanitizer.dart';

Map<String, dynamic> animeMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
int animeInt(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

/// Episodios que cuenta MyAnimeList al ver el episodio [number]: su parte
/// entera. Un especial «12.5» va después del 12, así que cuenta 12; «0.5»
/// no cuenta ninguno.
int malEpisodeCount(String number) {
  final value = double.tryParse(number);
  return value == null || !value.isFinite || value < 1 ? 0 : value.floor();
}

List<String> animeStrings(Object? value) => value is List
    ? value.map((e) => '$e').where((e) => e.isNotEmpty).toList()
    : [];

class AnimeTitle {
  final String slug, title, cover, synopsis, category, season, year, airing;
  final int sourceId, episodes, weekday;
  final List<String> genres, alternatives;
  final bool active;
  final double? score;
  final Map<String, dynamic> raw;
  AnimeTitle.fromJson(Map<String, dynamic> json)
    : slug = '${json['slug'] ?? ''}',
      title = TitleSanitizer.clean('${json['title'] ?? ''}'),
      cover = '${json['cover'] ?? ''}',
      synopsis = '${json['synopsis'] ?? ''}',
      category = '${json['category'] ?? ''}',
      season = '${json['season'] ?? ''}',
      year = '${json['year'] ?? ''}',
      airing = '${json['airing_status'] ?? ''}',
      sourceId = animeInt(json['source_id']),
      episodes = animeInt(json['episodes']),
      weekday = animeInt(json['weekday']),
      genres = animeStrings(json['genres']),
      alternatives = animeStrings(json['alternative_titles']),
      active = json['active'] == true,
      score = (json['mal_mean'] as num?)?.toDouble(),
      raw = Map.unmodifiable(json);
  Map<String, dynamic> toJson() => Map.from(raw);
}

class AnimeEpisode {
  final int id;
  final String slug, number, url;
  AnimeEpisode.fromJson(Map<String, dynamic> json)
    : id = animeInt(json['id']),
      slug = '${json['slug'] ?? ''}',
      number = '${json['number'] ?? ''}',
      url = '${json['url'] ?? ''}';
  String get key => '$slug:$number';
  Map<String, dynamic> toJson() => {
    'id': id,
    'slug': slug,
    'number': number,
    'url': url,
  };
}

class AnimeSeason {
  final String slug, title, label, category;
  AnimeSeason.fromJson(Map<String, dynamic> json)
    : slug = '${json['slug'] ?? ''}',
      title = '${json['title'] ?? ''}',
      label = '${json['label'] ?? json['title'] ?? ''}',
      category = '${json['category'] ?? ''}';
}

class AnimeDetail {
  final AnimeTitle anime;
  final List<AnimeEpisode> episodes;
  final List<AnimeSeason> seasons;
  final String warning;
  final Map<String, dynamic> raw;
  AnimeDetail.fromJson(Map<String, dynamic> json)
    : anime = AnimeTitle.fromJson(animeMap(json['anime'])),
      episodes =
          (json['episodes'] as List? ?? [])
              .map((e) => AnimeEpisode.fromJson(animeMap(e)))
              .toList()
            ..sort(
              (a, b) => (double.tryParse(a.number) ?? 0).compareTo(
                double.tryParse(b.number) ?? 0,
              ),
            ),
      seasons = (json['seasons'] as List? ?? [])
          .map((e) => AnimeSeason.fromJson(animeMap(e)))
          .toList(),
      warning = '${json['warning'] ?? ''}',
      raw = json;
}

class AnimePage {
  final List<AnimeTitle> items;
  final int page, pages, total;
  final List<String> years, seasons, genres, categories;
  final Map<String, dynamic> raw;
  AnimePage.fromJson(Map<String, dynamic> json)
    : items = (json['items'] as List? ?? [])
          .map((e) => AnimeTitle.fromJson(animeMap(e)))
          .toList(),
      page = animeInt(json['page'], 1),
      pages = animeInt(json['pages'], 1),
      total = animeInt(json['total']),
      years = animeStrings(json['years']),
      seasons = animeStrings(json['seasons']),
      genres = (json['genres'] as List? ?? [])
          .map((e) => e is Map ? '${e['name'] ?? e['genre'] ?? ''}' : '$e')
          .where((e) => e.isNotEmpty)
          .toList(),
      categories = animeStrings(json['categories']),
      raw = json;
}

class AnimePlaybackSource {
  final Uri url;
  final Map<String, String> headers;
  final String server;
  AnimePlaybackSource.fromJson(Map<String, dynamic> json)
    : url = Uri.parse(json['url'] as String),
      server = '${json['server'] ?? 'MP4Upload'}',
      headers = {
        'Referer': '${json['referer'] ?? ''}',
        'User-Agent': '${json['userAgent'] ?? ''}',
      };
}

class AnimeDownload {
  final Map<String, dynamic> raw;
  AnimeDownload(this.raw);
  String get key => '${raw['key']}';
  String get slug => '${raw['slug']}';
  String get number => '${raw['number']}';
  String get title => '${raw['title']}';
  String get state => '${raw['state']}';
  String get file => '${raw['file'] ?? ''}';
  String get error => '${raw['error'] ?? ''}';
  String get language => '${raw['language'] ?? 'SUB'}';
  int get bytes => animeInt(raw['bytes']);
  int get total => animeInt(raw['total']);
  bool get ready => state == 'done' && file.isNotEmpty;
}

class AnimeServer {
  final String language, server, embed;
  final bool supported;
  AnimeServer.fromJson(Map<String, dynamic> json)
    : language = '${json['language']}',
      server = '${json['server']}',
      embed = '${json['embed']}',
      supported = json['supported'] == true;
  String get label => '$language · $server';
}
