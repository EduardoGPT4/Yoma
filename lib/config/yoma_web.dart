/// Dirección de YomaTV (catálogo, web y puente de MyAnimeList).
///
/// Cambiar de dominio es cambiar [host]. [sites] son los dominios propios
/// aceptados como origen de confianza, cada uno con la ruta en la que vive
/// YomaTV. Durante un cambio de dominio se añade aquí el nuevo junto al
/// actual, para que el paso de uno a otro no deje fuera a ninguno.
class YomaWeb {
  static const host = 'tv.yoma.site';
  static const sites = {'tv.yoma.site': '/'};
  static Set<String> get hosts => sites.keys.toSet();

  /// Ruta de YomaTV en [host].
  static String get path => sites[host]!;
  static final base = Uri.parse('https://$host$path');

  /// [relative] dentro de la web (por ejemplo, `actions.php` o `#watch/1`).
  static Uri resolve(String relative) => base.resolve(relative);

  /// Ruta de [file] de YomaTV en el dominio de [uri], o `null` si no es
  /// un dominio propio.
  static String? pathOf(Uri uri, String file) {
    final root = sites[uri.host];
    return root == null ? null : '$root$file';
  }

  /// Es una dirección HTTPS de YomaTV, sin usuario ni puerto raro.
  static bool owns(Uri uri) {
    final root = sites[uri.host];
    return root != null &&
        uri.scheme == 'https' &&
        (uri.port == 443 || !uri.hasPort) &&
        uri.userInfo.isEmpty &&
        uri.path.startsWith(root);
  }
}
