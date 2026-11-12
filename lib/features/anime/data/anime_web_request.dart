import 'dart:convert';

/// Qué pide la web de YomaTV integrada en la app: reproducir un episodio,
/// descargarlo o elegir varios. La app lo hace con sus propias pantallas y su
/// cola local; la web no necesita la cuenta de tv.yoma.site para ello.
class AnimeWebRequest {
  final String action;
  final String slug;
  final int? episodeId;
  final String language;

  const AnimeWebRequest({
    required this.action,
    required this.slug,
    this.episodeId,
    this.language = 'SUB',
  });

  static const actions = {'play', 'download', 'episodes'};
  static final _slug = RegExp(r'^[A-Za-z0-9_-]{1,160}$');

  /// Devuelve `null` si el mensaje no es una petición válida.
  static AnimeWebRequest? parse(Object? raw) {
    try {
      final value = raw is String ? jsonDecode(raw) : raw;
      if (value is! Map) return null;
      final action = value['action'];
      final slug = value['slug'];
      if (!actions.contains(action) ||
          slug is! String ||
          !_slug.hasMatch(slug)) {
        return null;
      }
      final episode = value['episode_id'];
      final episodeId = episode is int ? episode : null;
      if (action != 'episodes' && (episodeId == null || episodeId <= 0)) {
        return null;
      }
      final language = '${value['language'] ?? 'SUB'}'.toUpperCase();
      if (!const {'SUB', 'LAT', 'DUB'}.contains(language)) return null;
      return AnimeWebRequest(
        action: action as String,
        slug: slug,
        episodeId: action == 'episodes' ? null : episodeId,
        language: language,
      );
    } on FormatException {
      return null;
    }
  }
}
