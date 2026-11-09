import 'package:flutter/foundation.dart';

import '../models/ui_density.dart';
import '../utils/preferences.dart';

class DensityProvider extends ChangeNotifier {
  UiDensity _density = UiDensity.compact;

  UiDensity get density => _density;
  bool get isCompact => _density == UiDensity.compact;

  Future<void> load() async {
    _density = UiDensity.fromName(await PreferencesService.getUiDensity());
    notifyListeners();
  }

  Future<void> setDensity(UiDensity value) async {
    if (_density == value) {
      return;
    }
    _density = value;
    notifyListeners();
    await PreferencesService.setUiDensity(value.name);
  }
}
