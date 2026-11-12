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

/// Servicios compartidos por YomaShi y YomaTV: el puente de MyAnimeList
/// (`yomashi-api.php`) y la sincronización. Viven en api.yoma.site, separados
/// del hosting web de YomaTV, con la misma base de datos.
class YomaServices {
  static const host = 'api.yoma.site';
  static const path = '/';
  static final base = Uri.parse('https://$host$path');
  static Uri resolve(String file) => base.resolve(file);

  /// API del puente de MyAnimeList.
  static final malApi = resolve('yomashi-api.php');

  /// El mismo puente en tv.yoma.site (misma base de datos). Se usa mientras
  /// api.yoma.site no responde, por ejemplo antes de activar su SSL.
  static const legacyHost = 'tv.yoma.site';
  static final legacyMalApi = Uri.parse('https://$legacyHost/yomashi-api.php');

  /// La autorización en el navegador sigue en tv.yoma.site: es la dirección
  /// de retorno registrada en la aplicación de MyAnimeList.
  static const connectHost = 'tv.yoma.site';

  /// Página para conectar MyAnimeList: HTTPS de [connectHost] en el puerto
  /// 443, sin usuario y en su ruta exacta.
  static bool isConnectPage(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host == connectHost &&
      (uri.port == 443 || !uri.hasPort) &&
      uri.userInfo.isEmpty &&
      uri.path == '/yomashi-connect.php';
}
