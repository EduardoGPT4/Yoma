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
      'https://tv.yoma.site/yomashi-api.php',
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

  test('los servicios compartidos tienen su propia dirección', () {
    // YomaShi no depende de la dirección de YomaTV: el puente de MAL tiene
    // la suya (hoy, el mismo hosting).
    expect(MyAnimeListClient.endpoint, YomaServices.malApi);
    expect(
      YomaServices.malApi.toString(),
      'https://${YomaServices.host}${YomaServices.path}yomashi-api.php',
    );
    for (final ok in [
      'https://tv.yoma.site/yomashi-connect.php?device=1',
      'https://tv.yoma.site:443/yomashi-connect.php',
    ]) {
      expect(YomaServices.isConnectPage(Uri.parse(ok)), isTrue, reason: ok);
    }
    for (final bad in [
      'http://tv.yoma.site/yomashi-connect.php',
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
  });
}
