import 'package:flutter/material.dart';

import '../utils/preferences.dart';

/// Color de acento del tema; notifica al cambiar (aplicación en caliente).
class ThemeAccentProvider extends ChangeNotifier {
  static const Color defaultAccent = Color(0xFF7C3AED);

  Color _primary = defaultAccent;
  bool _loaded = false;

  Color get primary => _primary;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    final stored = await PreferencesService.getThemeAccent();
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
