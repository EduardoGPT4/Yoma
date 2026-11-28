import '../models/anime_models.dart';

/// Animes parecidos por el nombre, para la sección «Animes similares» de la
/// ficha.
///
/// Cada título se reduce a su nombre base: sin acentos ni signos, sin el
/// subtítulo que va tras «: » o « - » y sin las coletillas de temporada,
/// parte o formato del final («Season 2», «2nd Season», «Part 2», «Movie»,
/// «OVA», números). Dos títulos con el mismo nombre base son de la misma
/// franquicia; si no, se comparan sus palabras.
class AnimeSimilarity {
  AnimeSimilarity._();

  /// Tarjetas que se muestran como mucho.
  static const limit = 12;

  /// Parecido mínimo para entrar en la lista. Dos palabras importantes de
  /// cuatro en común (la mitad) dan justo este valor.
  static const threshold = 0.4;

  static final _separators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
  static final _subtitle = RegExp(r'\s*[:：]\s+|\s+[-–—~]\s+');
  static final _number = RegExp(
    r'^(?:\d+(?:st|nd|rd|th|da|do|ra|ro|ta|to|er|a|o)?|s\d+|ii|iii|iv|vi|vii|viii|ix)$',
  );

  static const _accents = {
    'á': 'a',
    'à': 'a',
    'ä': 'a',
    'â': 'a',
    'ã': 'a',
    'å': 'a',
    'ā': 'a',
    'é': 'e',
    'è': 'e',
    'ë': 'e',
    'ê': 'e',
    'ē': 'e',
    'í': 'i',
    'ì': 'i',
    'ï': 'i',
    'î': 'i',
    'ī': 'i',
    'ó': 'o',
    'ò': 'o',
    'ö': 'o',
    'ô': 'o',
    'õ': 'o',
    'ō': 'o',
    'ú': 'u',
    'ù': 'u',
    'ü': 'u',
    'û': 'u',
    'ū': 'u',
    'ñ': 'n',
    'ç': 'c',
  };

  /// Coletillas del final que no cambian la obra: temporada, parte, formato.
  static const _suffixes = {
    'season',
    'seasons',
    'temporada',
    'temporadas',
    'part',
    'parte',
    'cour',
    'movie',
    'movies',
    'pelicula',
    'peliculas',
    'film',
    'gekijouban',
    'ova',
    'ovas',
    'ona',
    'oad',
    'special',
    'specials',
    'especial',
    'especiales',
    'tv',
    'second',
    'third',
    'fourth',
    'fifth',
    'sixth',
    'segunda',
    'tercera',
    'cuarta',
    'quinta',
  };

  /// Solo se quitan del final detrás de otra coletilla: «The Final Season»,
  /// «the Movie».
  static const _trailingAfterSuffix = {'the', 'final', 'la', 'el'};

  static const _prefixes = {'gekijouban', 'gekijoban', 'eiga'};

  /// Partículas y artículos que no distinguen un título de otro.
  static const _stopwords = {
    'no', 'wa', 'ga', 'wo', 'o', 'to', 'ni', 'na', 'de', 'e', 'mo', 'ka',
    'the', 'a', 'an', 'of', 'and', 'in', 'on', 'la', 'el', 'los', 'las',
    'y', 'del', 'en',
    // Tratamientos: «Pii-chan» no se parece a «A-Channel».
    'chan', 'san', 'kun', 'sama', 'tan',
  };

  /// Minúsculas, sin acentos y con las palabras separadas por un espacio.
  static String normalize(String title) {
    final lower = title.toLowerCase();
    final plain = StringBuffer();
    for (final char in lower.split('')) {
      plain.write(_accents[char] ?? char);
    }
    return plain.toString().replaceAll(_separators, ' ').trim();
  }

  static List<String> _words(String title) {
    final text = normalize(title);
    return text.isEmpty ? [] : text.split(' ');
  }

  /// Palabras del nombre base de [title].
  static List<String> base(String title) {
    final cut = title.split(_subtitle).first;
    var words = _words(cut);
    // Un nombre de una o dos letras antes de «: » no basta: es parte del
    // título.
    if (words.join().length < 3) words = _words(title);
    while (words.length > 1 && _prefixes.contains(words.first)) {
      words = words.sublist(1);
    }
    var popped = false;
    while (words.length > 1) {
      final last = words.last;
      if (_number.hasMatch(last) || _suffixes.contains(last)) {
        popped = true;
      } else if (!popped || !_trailingAfterSuffix.contains(last)) {
        break;
      }
      words = words.sublist(0, words.length - 1);
    }
    return words;
  }

  /// Palabras que distinguen el título; si todas son partículas, todas.
  static List<String> _significant(List<String> words) {
    final kept = words.where((w) => !_stopwords.contains(w)).toList();
    return kept.isEmpty ? words : kept;
  }

  /// Como [_significant], sin coletillas de temporada, parte o formato.
  static List<String> _distinctive(List<String> words) {
    final kept = _significant(
      words,
    ).where((w) => !_suffixes.contains(w) && !_number.hasMatch(w)).toList();
    return kept.isEmpty ? _significant(words) : kept;
  }

  static bool _sameWord(String a, String b) {
    if (a == b) return true;
    final (short, long) = a.length <= b.length ? (a, b) : (b, a);
    // Plurales y variantes cortas («Hero» y «Heroes»), no otra palabra que
    // empieza igual («Gate» y «Gatekeepers»).
    return short.length >= 4 &&
        long.length - short.length <= 2 &&
        long.startsWith(short);
  }

  /// Parecido entre dos nombres, de 0 a 1.
  static double nameScore(String a, String b) {
    final baseA = base(a), baseB = base(b);
    if (baseA.isEmpty || baseB.isEmpty) return 0;
    // Mismo nombre base: misma franquicia («Re:Zero» y «Re Zero» también).
    if (baseA.join() == baseB.join()) return 1;
    // Uno empieza por el otro palabra a palabra: «Naruto» y «Naruto
    // Shippuden».
    final (short, long) = baseA.length <= baseB.length
        ? (baseA, baseB)
        : (baseB, baseA);
    var prefix = true;
    for (var i = 0; i < short.length; i++) {
      if (short[i] != long[i]) {
        prefix = false;
        break;
      }
    }
    if (prefix && short.join().length >= 4) {
      return 0.8 + 0.15 * short.join().length / long.join().length;
    }
    // Palabras importantes en común (coeficiente de Dice). Las coletillas
    // no cuentan: «Season 2 Part 2» no acerca dos obras distintas.
    final wordsA = _distinctive(_words(a)), wordsB = _distinctive(_words(b));
    final unused = [...wordsB];
    var common = 0;
    for (final word in wordsA) {
      final index = unused.indexWhere((other) => _sameWord(word, other));
      if (index < 0) continue;
      common++;
      unused.removeAt(index);
    }
    return 0.8 * 2 * common / (wordsA.length + wordsB.length);
  }

  /// Parecido entre dos animes: el mejor entre sus títulos y alternativos.
  static double score(AnimeTitle anime, AnimeTitle other) {
    var best = 0.0;
    for (final a in [anime.title, ...anime.alternatives]) {
      for (final b in [other.title, ...other.alternatives]) {
        final value = nameScore(a, b);
        if (value > best) best = value;
      }
    }
    return best;
  }

  /// Los [limit] candidatos más parecidos a [anime], sin repetir ni incluir
  /// [anime] ni los de [exclude]. A igual parecido, por año y por título.
  static List<AnimeTitle> rank(
    AnimeTitle anime,
    Iterable<AnimeTitle> candidates, {
    Set<String> exclude = const {},
    int limit = limit,
  }) {
    final seen = {anime.slug, ...exclude};
    final scored = <(AnimeTitle, double)>[];
    for (final other in candidates) {
      if (other.slug.isEmpty || !seen.add(other.slug)) continue;
      final value = score(anime, other);
      if (value >= threshold) scored.add((other, value));
    }
    int year(AnimeTitle a) => int.tryParse(a.year) ?? 9999;
    scored.sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      if (byScore != 0) return byScore;
      final byYear = year(a.$1).compareTo(year(b.$1));
      if (byYear != 0) return byYear;
      return a.$1.title.toLowerCase().compareTo(b.$1.title.toLowerCase());
    });
    return [for (final (item, _) in scored.take(limit)) item];
  }

  /// Búsquedas en el catálogo de YomaTV que traen los candidatos: el nombre
  /// base (la franquicia) y su palabra más larga (los parecidos).
  static List<String> queries(AnimeTitle anime) {
    final words = base(anime.title);
    if (words.isEmpty) return [];
    final queries = [words.join(' ')];
    final significant = _significant(words);
    if (significant.length > 1) {
      final longest = significant.reduce((a, b) => b.length > a.length ? b : a);
      if (longest.length >= 4) queries.add(longest);
    }
    return queries;
  }
}
