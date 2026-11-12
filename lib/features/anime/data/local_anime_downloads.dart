import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import '../models/anime_models.dart';

/// Texto de un error para mostrarlo en pantalla. Los fallos del reproductor
/// y de las descargas llegan de Android como [PlatformException]; se muestra
/// su mensaje y no «PlatformException(anime_local, …, null, null)».
String animeErrorText(Object error) {
  if (error is PlatformException) {
    final message = error.message?.trim() ?? '';
    return message.isEmpty
        ? 'No se pudo completar la operación en el dispositivo.'
        : message;
  }
  return error.toString();
}

class LocalAnimeDownloads {
  static const channel = MethodChannel('app.yoma/anime_local');
  Future<Map<String, dynamic>> snapshot() async {
    if (!Platform.isAndroid) {
      return {
        'items': <dynamic>[],
        'supported': false,
        'wifiOnly': true,
        'paused': false,
      };
    }
    return animeMap(
      jsonDecode((await channel.invokeMethod<String>('snapshot'))!),
    );
  }

  Map<String, dynamic> payload(
    AnimeTitle anime,
    AnimeEpisode episode,
    String language,
  ) => {
    'slug': anime.slug,
    'title': anime.title,
    'cover': anime.cover,
    'season': anime.season,
    'episode_id': episode.id,
    'number': episode.number,
    'language': language,
  };

  /// Pide la descarga y devuelve qué pasó: `added`, `requeued` (había
  /// fallado, estaba en pausa o faltaba su archivo), `exists` (ya en la
  /// cola) o `done` (ya descargado).
  Future<String> enqueue(
    AnimeTitle anime,
    AnimeEpisode episode,
    String language,
  ) async =>
      await channel.invokeMethod<String>(
        'enqueue',
        jsonEncode(payload(anime, episode, language)),
      ) ??
      'added';
  Future<List<AnimeServer>> sources(
    AnimeTitle anime,
    AnimeEpisode episode,
  ) async {
    if (!Platform.isAndroid) {
      throw const AnimeSourceFailureCompat(
        'La reproducción de esta fuente está disponible en Android.',
      );
    }
    final data =
        jsonDecode(
              (await channel.invokeMethod<String>(
                'sources',
                jsonEncode(payload(anime, episode, 'SUB')),
              ))!,
            )
            as List;
    return data.map((e) => AnimeServer.fromJson(animeMap(e))).toList();
  }

  Future<AnimePlaybackSource> resolve(
    AnimeTitle anime,
    AnimeEpisode episode,
    String language, {
    String? embed,
  }) async {
    if (!Platform.isAndroid) {
      throw const AnimeSourceFailureCompat(
        'La resolución nativa de este servidor está disponible en Android.',
      );
    }
    return AnimePlaybackSource.fromJson(
      animeMap(
        jsonDecode(
          (await channel.invokeMethod<String>(
            'resolve',
            jsonEncode({...payload(anime, episode, language), 'embed': ?embed}),
          ))!,
        ),
      ),
    );
  }

  /// Pasa a la cola local lo que quedaba en la cola de la cuenta web:
  /// mueve los episodios descargados, vuelve a pedir los pendientes y
  /// devuelve el progreso visto (`progress`) para el historial.
  Future<Map<String, dynamic>> adoptWeb() async {
    if (!Platform.isAndroid) return const {};
    final raw = await channel.invokeMethod<String>('adoptWeb');
    return raw == null ? const {} : animeMap(jsonDecode(raw));
  }

  /// Mueve los episodios ya descargados a Yoma/YomaTV/Anime. Devuelve
  /// cuántos se movieron (0 si falta el permiso o hay una descarga activa).
  Future<int> migrate() async {
    if (!Platform.isAndroid) return 0;
    return await channel.invokeMethod<int>('migrate') ?? 0;
  }

  Future<void> control(String action, {String? key, bool? value}) =>
      channel.invokeMethod<void>(
        'control',
        jsonEncode({'action': action, 'key': ?key, 'value': ?value}),
      );
}

class AnimeSourceFailureCompat implements Exception {
  final String message;
  const AnimeSourceFailureCompat(this.message);
  @override
  String toString() => message;
}
