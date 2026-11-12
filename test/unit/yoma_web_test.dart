import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/config/yoma_web.dart';
import 'package:yomashi/features/anime/anime_screen.dart';
import 'package:yomashi/features/anime/data/yomatv_source.dart';
import 'package:yomashi/services/myanimelist_client.dart';

void main() {
  test('YomaTV vive en la raíz de tv.yoma.site', () {
    expect(YomaWeb.base.toString(), 'https://tv.yoma.site/');
    expect(YomaTvSource.origin, YomaWeb.base);
    expect(AnimeScreenState.site, YomaWeb.base);
    expect(
      MyAnimeListClient.endpoint.toString(),
      // El puente de MAL ya no es de YomaTV (ver «servicios compartidos»).
      'https://api.yoma.site/yomashi-api.php',
    );
    expect(
      YomaWeb.resolve('#watch/12').toString(),
      'https://tv.yoma.site/#watch/12',
    );
  });

  test('solo tv.yoma.site es YomaTV', () {
    for (final uri in [
      'https://tv.yoma.site/',
      'https://tv.yoma.site/yomashi-connect.php',
    ]) {
      expect(YomaWeb.owns(Uri.parse(uri)), isTrue, reason: uri);
    }
    for (final uri in [
      // El dominio anterior ya no tiene la web (redirige a un error 404).
      'https://hk-br035.gt.tc/seasonav1/',
      // La página principal y YomaShi no son YomaTV.
      'https://yoma.site/',
      'https://shi.yoma.site/',
      'http://tv.yoma.site/',
      'https://tv.yoma.site.evil.com/',
      'https://tv.yoma.site:8443/',
      'https://user@tv.yoma.site/',
    ]) {
      expect(YomaWeb.owns(Uri.parse(uri)), isFalse, reason: uri);
    }
  });

  test('la conexión con MAL se abre en tv.yoma.site', () {
    expect(
      YomaWeb.pathOf(
        Uri.parse('https://tv.yoma.site/x'),
        'yomashi-connect.php',
      ),
      '/yomashi-connect.php',
    );
    expect(
      YomaWeb.pathOf(
        Uri.parse('https://hk-br035.gt.tc/x'),
        'yomashi-connect.php',
      ),
      isNull,
    );
  });

  test('los servicios compartidos viven en api.yoma.site', () {
    // YomaShi no depende de la dirección de YomaTV: el puente de MAL está en
    // api.yoma.site, con tv.yoma.site como respaldo mientras api no responda.
    expect(MyAnimeListClient.endpoint, YomaServices.malApi);
    expect(
      YomaServices.malApi.toString(),
      'https://api.yoma.site/yomashi-api.php',
    );
    expect(
      YomaServices.legacyMalApi.toString(),
      'https://tv.yoma.site/yomashi-api.php',
    );
    final client = MyAnimeListClient();
    expect(client.api, YomaServices.malApi);
    expect(client.fallback, YomaServices.legacyMalApi);
    client.http.close(force: true);
    // La autorización sigue en tv.yoma.site (dirección de retorno de MAL).
    for (final ok in [
      'https://tv.yoma.site/yomashi-connect.php?device=1',
      'https://tv.yoma.site:443/yomashi-connect.php',
    ]) {
      expect(YomaServices.isConnectPage(Uri.parse(ok)), isTrue, reason: ok);
    }
    for (final bad in [
      'http://tv.yoma.site/yomashi-connect.php',
      'https://api.yoma.site/yomashi-connect.php',
      'https://tv.yoma.site/otra.php',
      'https://tv.yoma.site.evil.com/yomashi-connect.php',
      'https://user@tv.yoma.site/yomashi-connect.php',
      'https://tv.yoma.site:8443/yomashi-connect.php',
      'https://yoma.site/yomashi-connect.php',
    ]) {
      expect(YomaServices.isConnectPage(Uri.parse(bad)), isFalse, reason: bad);
    }
    // Android usa los mismos valores.
    final kotlin = File(
      'android/app/src/main/kotlin/app/yomashi/reader/YomaWeb.kt',
    ).readAsStringSync();
    final services = kotlin.substring(kotlin.indexOf('object YomaServices'));
    expect(services, contains('const val HOST = "${YomaServices.host}"'));
    expect(services, contains('const val PATH = "${YomaServices.path}"'));
    expect(
      services,
      contains('const val CONNECT_HOST = "${YomaServices.connectHost}"'),
    );
  });
}
