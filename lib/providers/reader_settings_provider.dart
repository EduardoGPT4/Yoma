import '../data/library_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

import '../models/reader_settings_enums.dart';
import '../utils/preferences.dart';

class ReaderSettingsProvider extends ChangeNotifier {
  bool _cropWhite = false;
  String _orientation = 'system';
  bool get cropWhite => _cropWhite;
  String get orientation => _orientation;
  Future<void> setCropWhite(bool value) async {
    _cropWhite = value;
    await _save(() async {
      await (await SharedPreferences.getInstance()).setBool(
        'reader_crop_white_v1',
        value,
      );
    });
    notifyListeners();
  }

  Future<void> setOrientation(String value) async {
    if (!{'system', 'portrait', 'landscape'}.contains(value)) return;
    _orientation = value;
    await _save(() async {
      await (await SharedPreferences.getInstance()).setString(
        'reader_orientation_v1',
        value,
      );
    });
    notifyListeners();
  }

  String? _mangaKey;
  Map<String, dynamic>? _global;
  bool _continuous = false;
  bool _coverAlone = true;
  bool get coverAlone => _coverAlone;
  Future<void> setCoverAlone(bool value) async {
    _coverAlone = value;
    await _save(() async {
      await (await SharedPreferences.getInstance()).setBool(
        'reader_cover_alone_v1',
        value,
      );
    });
    notifyListeners();
  }

  bool get continuousVertical => _continuous;
  Map<String, dynamic> _snapshot() => {
    'cropWhite': _cropWhite,
    'orientation': _orientation,
    'direction': _readingDirection.name,
    'fit': _pageFitMode.name,
    'zoom': _freeZoom,
    'double': _doublePage,
    'continuous': _continuous,
    'coverAlone': _coverAlone,
  };
  Future<void> bindManga(String key) async {
    _global ??= _snapshot();
    _mangaKey = key;
    _apply(_global!);
    final value = await (await LibraryStore.ensureInitialized()).getRecord(
      'reader',
      key,
    );
    if (_mangaKey != key) return;
    if (value is Map) _apply(Map<String, dynamic>.from(value));
    notifyListeners();
  }

  void _apply(Map<String, dynamic> map) {
    _cropWhite = map['cropWhite'] as bool? ?? false;
    _orientation =
        {'system', 'portrait', 'landscape'}.contains(map['orientation'])
        ? map['orientation'] as String
        : 'system';
    _readingDirection = ReadingDirection.values.firstWhere(
      (e) => e.name == map['direction'],
      orElse: () => _readingDirection,
    );
    _pageFitMode = PageFitMode.values.firstWhere(
      (e) => e.name == map['fit'],
      orElse: () => _pageFitMode,
    );
    _freeZoom = map['zoom'] as bool? ?? _freeZoom;
    _doublePage = map['double'] as bool? ?? _doublePage;
    _continuous = map['continuous'] as bool? ?? _continuous;
    _coverAlone = map['coverAlone'] as bool? ?? _coverAlone;
  }

  Future<void> unbindManga() async {
    _mangaKey = null;
    if (_global != null) _apply(_global!);
    _global = null;
    notifyListeners();
  }

  Future<void> _save(Future<void> Function() global) async {
    final key = _mangaKey;
    if (key == null) {
      await global();
    } else {
      await (await LibraryStore.ensureInitialized()).putRecord('reader', key, {
        'id': key,
        ..._snapshot(),
      });
    }
  }

  Future<void> setContinuousVertical(bool value) async {
    _continuous = value;
    if (value) _readingDirection = ReadingDirection.vertical;
    if (value) _doublePage = false;
    await _save(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('reader_continuous_v1', value);
      await PreferencesService.setReadingDirection(_readingDirection);
      await PreferencesService.setDoublePage(_doublePage);
    });
    notifyListeners();
  }

  ReadingDirection _readingDirection = ReadingDirection.rightToLeft;
  PageFitMode _pageFitMode = PageFitMode.fitWidth;
  bool _freeZoom = true;
  PageTransitionSpeed _transitionSpeed = PageTransitionSpeed.normal;
  bool _showPageNumber = true;
  bool _tapNavigation = true;
  bool _volumeNavigation = true;
  bool _doublePage = false;
  double _appBrightness = 1.0;

  ReadingDirection get readingDirection => _readingDirection;
  bool get verticalMode => _readingDirection == ReadingDirection.vertical;
  bool get isHorizontal => !verticalMode;
  bool get isRightToLeft => _readingDirection == ReadingDirection.rightToLeft;
  PageFitMode get pageFitMode => _pageFitMode;
  bool get freeZoom => _freeZoom;
  PageTransitionSpeed get transitionSpeed => _transitionSpeed;
  Duration get transitionDuration => _transitionSpeed.duration;
  bool get showPageNumber => _showPageNumber;
  bool get tapNavigation => _tapNavigation;
  bool get volumeNavigation => _volumeNavigation;
  bool get doublePage => _doublePage;
  double get appBrightness => _appBrightness;
  double get dimOpacity => (1.0 - _appBrightness).clamp(0.0, 0.85).toDouble();

  Future<void> load() async {
    final extra = await SharedPreferences.getInstance();
    _cropWhite = extra.getBool('reader_crop_white_v1') ?? false;
    _orientation = extra.getString('reader_orientation_v1') ?? 'system';
    _coverAlone =
        (await SharedPreferences.getInstance()).getBool(
          'reader_cover_alone_v1',
        ) ??
        true;
    _continuous =
        (await SharedPreferences.getInstance()).getBool(
          'reader_continuous_v1',
        ) ??
        false;
    _readingDirection = await PreferencesService.getReadingDirection();
    _pageFitMode = await PreferencesService.getPageFitMode();
    _freeZoom = await PreferencesService.getFreeZoom();
    _transitionSpeed = await PreferencesService.getTransitionSpeed();
    _showPageNumber = await PreferencesService.getShowPageNumber();
    _tapNavigation = await PreferencesService.getTapNavigation();
    _volumeNavigation = await PreferencesService.getVolumeNavigation();
    _doublePage = await PreferencesService.getDoublePage();
    _appBrightness = await PreferencesService.getAppBrightness();
    notifyListeners();
  }

  Future<void> setReadingDirection(ReadingDirection value) async {
    if (_readingDirection == value) {
      return;
    }
    _readingDirection = value;
    if (value != ReadingDirection.vertical) {
      _continuous = false;
      await _save(() async {
        await (await SharedPreferences.getInstance()).setBool(
          'reader_continuous_v1',
          false,
        );
      });
    }
    if (value == ReadingDirection.vertical) {
      _doublePage = false;
      await _save(() => PreferencesService.setDoublePage(false));
    }
    notifyListeners();
    await _save(() => PreferencesService.setReadingDirection(value));
  }

  Future<void> toggleMode() async {
    final next = switch (_readingDirection) {
      ReadingDirection.rightToLeft => ReadingDirection.leftToRight,
      ReadingDirection.leftToRight => ReadingDirection.vertical,
      ReadingDirection.vertical => ReadingDirection.rightToLeft,
    };
    await setReadingDirection(next);
  }

  Future<void> setPageFitMode(PageFitMode value) async {
    if (_pageFitMode == value) {
      return;
    }
    _pageFitMode = value;
    notifyListeners();
    await _save(() => PreferencesService.setPageFitMode(value));
  }

  Future<void> setFreeZoom(bool value) async {
    if (_freeZoom == value) {
      return;
    }
    _freeZoom = value;
    notifyListeners();
    await _save(() => PreferencesService.setFreeZoom(value));
  }

  Future<void> setTransitionSpeed(PageTransitionSpeed value) async {
    if (_transitionSpeed == value) {
      return;
    }
    _transitionSpeed = value;
    notifyListeners();
    await PreferencesService.setTransitionSpeed(value);
  }

  Future<void> setShowPageNumber(bool value) async {
    if (_showPageNumber == value) {
      return;
    }
    _showPageNumber = value;
    notifyListeners();
    await PreferencesService.setShowPageNumber(value);
  }

  Future<void> setTapNavigation(bool value) async {
    if (_tapNavigation == value) {
      return;
    }
    _tapNavigation = value;
    notifyListeners();
    await PreferencesService.setTapNavigation(value);
  }

  Future<void> setVolumeNavigation(bool value) async {
    if (_volumeNavigation == value) {
      return;
    }
    _volumeNavigation = value;
    notifyListeners();
    await PreferencesService.setVolumeNavigation(value);
  }

  Future<void> setDoublePage(bool value) async {
    if (_doublePage == value) {
      return;
    }
    if (value && verticalMode) {
      return;
    }
    _doublePage = value;
    notifyListeners();
    await _save(() => PreferencesService.setDoublePage(value));
  }

  Future<void> setAppBrightness(double value) async {
    final nextValue = value.clamp(0.0, 1.0).toDouble();
    if (nextValue == _appBrightness) {
      return;
    }
    _appBrightness = nextValue;
    notifyListeners();
    await PreferencesService.setAppBrightness(_appBrightness);
  }
}
