import 'package:flutter/material.dart';

import '../design/yoma_tokens.dart';
import '../utils/preferences.dart';

/// Color de acento del tema; notifica al cambiar (aplicación en caliente).
class ThemeAccentProvider extends ChangeNotifier {
  static const Color defaultAccent = YomaColors.accent;

  Color _primary = defaultAccent;
  bool _loaded = false;

  Color get primary => _primary;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    var stored = await PreferencesService.getThemeAccent();
    // Una sola vez: el violeta por defecto y el rojo saturado anteriores pasan
    // al coral de Yoma. Los demás colores elegidos se conservan.
    if (await PreferencesService.takeYomaAccentMigration() &&
        stored != null &&
        YomaColors.legacyAccents.contains(stored)) {
      await PreferencesService.setThemeAccent(null);
      stored = null;
    }
    _primary = stored == null ? defaultAccent : Color(stored);
    _loaded = true;
    notifyListeners();
  }

  Future<void> setAccent(Color color) async {
    if (_primary.toARGB32() == color.toARGB32()) {
      return;
    }
    _primary = color;
    await PreferencesService.setThemeAccent(color.toARGB32());
    notifyListeners();
  }

  Future<void> reset() => setAccent(defaultAccent);
}
