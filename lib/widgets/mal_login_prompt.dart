import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design/yoma_tokens.dart';
import '../services/myanimelist_client.dart';
import '../services/myanimelist_service.dart';

/// Al abrir la app por primera vez propone entrar con MyAnimeList.
///
/// - «Iniciar sesión con MyAnimeList» abre la conexión de siempre: la cuenta
///   de Yoma es la de tu ID de MAL, la misma en la web y en otros teléfonos.
/// - «Continuar sin cuenta» deja la app en local. Lo guardado aquí se sube a
///   tu cuenta cuando conectes MyAnimeList más tarde (desde la tarjeta del
///   inicio o desde Más): YomaTV (AnimeSync) y el manga online (MangaSync).
///
/// Se pregunta una sola vez por instalación y nunca con MAL ya conectado.
class MalLoginPrompt extends StatelessWidget {
  static const askedKey = 'yoma.mal_login_asked';

  final VoidCallback onLogin;
  const MalLoginPrompt({super.key, required this.onLogin});

  /// Muestra la propuesta si toca. Devuelve si se mostró.
  static Future<bool> maybeShow(
    BuildContext context, {
    required VoidCallback onLogin,
    MalCredentialStore? credentials,
  }) async {
    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return false;
    }
    if (prefs.getBool(askedKey) == true) return false;
    final store = credentials ?? MyAnimeListService.shared.client.credentials;
    Map<String, dynamic>? session;
    try {
      session = await store.load();
    } catch (_) {
      // Sin acceso a las credenciales no se insiste ahora; se volverá a
      // proponer en el siguiente inicio.
      return false;
    }
    if (session?['connected'] == true) {
      await prefs.setBool(askedKey, true);
      return false;
    }
    if (!context.mounted) return false;
    // Se guarda antes de mostrarla: cerrarla de cualquier forma cuenta como
    // respuesta y no vuelve a aparecer.
    await prefs.setBool(askedKey, true);
    if (!context.mounted) return false;
    final login = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) =>
          MalLoginPrompt(onLogin: () => Navigator.pop(sheet, true)),
    );
    if (login == true) onLogin();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      // Por encima de la barra de navegación del sistema.
      padding: EdgeInsets.fromLTRB(
        24,
        4,
        24,
        24 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'BIENVENIDO A YOMA',
            style: text.labelMedium?.copyWith(
              color: YomaColors.accent,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Entra con tu MyAnimeList',
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            'Tu anime te sigue entre este teléfono, otros dispositivos y la '
            'web; tu manga online, entre tus teléfonos. Tus listas de MAL se '
            'actualizan solas. La primera vez se crea tu cuenta sola, sin '
            'contraseña.',
            style: text.bodyMedium?.copyWith(color: YomaColors.textSecondary),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: onLogin,
            icon: const Icon(Icons.login),
            label: const Text('Iniciar sesión con MyAnimeList'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuar sin cuenta'),
          ),
          const SizedBox(height: 6),
          Text(
            'Sin cuenta, todo se guarda en este teléfono. Si conectas '
            'MyAnimeList después, tu biblioteca y tu progreso (anime y manga '
            'online) se suben a tu cuenta.',
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: YomaColors.textMuted),
          ),
        ],
      ),
    );
  }
}
