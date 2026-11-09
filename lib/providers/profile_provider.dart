import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/preferences.dart';
import '../services/myanimelist_client.dart';
import '../services/myanimelist_service.dart';

/// MAL provides the visible identity while connected; the local name is retained.
class ProfileProvider extends ChangeNotifier {
  static const defaultDisplayName = 'Lector';
  final MyAnimeListClient _malClient;
  ProfileProvider({MyAnimeListClient? malClient})
    : _malClient = malClient ?? MyAnimeListService.shared.client {
    _malClient.sessionChanges.addListener(_onSessionChanged);
  }

  String _displayName = defaultDisplayName;
  String? _avatarPath;
  bool _loaded = false;
  bool _disposed = false;
  int _identityGeneration = 0;
  int? _malUserId;
  String? _malUsername;
  String? _malAvatarUrl;
  Future<void>? _refreshingAccount;

  String get displayName => _malUsername ?? _displayName;
  String? get myAnimeListUsername => _malUsername;
  String? get myAnimeListAvatarUrl => _malAvatarUrl;
  bool get usesMyAnimeListIdentity => _malUsername != null;
  String? get avatarPath => _avatarPath;
  bool get isLoaded => _loaded;

  void _onSessionChanged() => unawaited(reloadMyAnimeListIdentity());

  /// Only reads encrypted local credentials; safe to call without a network.
  Future<void> reloadMyAnimeListIdentity() async {
    if (_disposed) return;
    final generation = ++_identityGeneration;
    Map<String, dynamic>? auth;
    try {
      auth = await _malClient.credentials.load();
    } catch (_) {
      return;
    }
    if (_disposed || generation != _identityGeneration) return;
    final profile = auth?['profile'];
    final id = profile is Map ? profile['id'] : null;
    final name = profile is Map ? profile['name'] : null;
    final connected =
        auth?['connected'] == true &&
        id is int &&
        id > 0 &&
        name is String &&
        name.trim().isNotEmpty;
    final nextName = connected ? name.trim() : null;
    final nextId = connected ? id : null;
    final picture = profile is Map ? profile['picture'] : null;
    final nextAvatar = connected ? _validatedAvatar(picture) : null;
    if (_malUsername == nextName &&
        _malUserId == nextId &&
        _malAvatarUrl == nextAvatar) {
      return;
    }
    _malUsername = nextName;
    _malUserId = nextId;
    _malAvatarUrl = nextAvatar;
    notifyListeners();
  }

  static String? _validatedAvatar(Object? value) {
    if (value is! String ||
        value.length > 2048 ||
        RegExp(r'[\x00-\x20\\]').hasMatch(value)) {
      return null;
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'cdn.myanimelist.net' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      return null;
    }
    return value;
  }

  /// Refreshes session status without hiding the cached identity while offline.
  Future<void> refreshMyAnimeList() {
    if (_disposed) return Future.value();
    return _refreshingAccount ??= _refreshMyAnimeList().whenComplete(
      () => _refreshingAccount = null,
    );
  }

  Future<void> _refreshMyAnimeList() async {
    await reloadMyAnimeListIdentity();
    if (_disposed) return;
    try {
      await _malClient.account();
    } catch (_) {
      // A 401 clears credentials in the client. Network failures preserve them.
    }
    await reloadMyAnimeListIdentity();
  }

  @override
  void dispose() {
    _disposed = true;
    _identityGeneration++;
    _malClient.sessionChanges.removeListener(_onSessionChanged);
    super.dispose();
  }

  bool get hasAvatar {
    final path = _avatarPath;
    if (path == null || path.isEmpty) {
      return false;
    }
    return File(path).existsSync();
  }

  Future<void> load() async {
    final name = await PreferencesService.getProfileDisplayName();
    final avatar = await PreferencesService.getProfileAvatarPath();
    if (_disposed) return;
    _displayName = (name == null || name.trim().isEmpty)
        ? defaultDisplayName
        : name.trim();
    _avatarPath = avatar;
    if (_avatarPath != null && !File(_avatarPath!).existsSync()) {
      _avatarPath = null;
      await PreferencesService.setProfileAvatarPath(null);
    }
    _loaded = true;
    await reloadMyAnimeListIdentity();
    if (_disposed) return;
    notifyListeners();
    unawaited(refreshMyAnimeList());
  }

  Future<void> setDisplayName(String name) async {
    final cleaned = name.trim();
    final next = cleaned.isEmpty ? defaultDisplayName : cleaned;
    if (next == _displayName) {
      return;
    }
    _displayName = next;
    notifyListeners();
    await PreferencesService.setProfileDisplayName(
      next == defaultDisplayName ? null : next,
    );
  }

  /// Copia la imagen elegida a almacenamiento de la app y la guarda.
  Future<void> setAvatarFromFile(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      return;
    }

    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'profile'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final ext = p.extension(sourcePath).toLowerCase();
    final safeExt =
        (ext == '.png' || ext == '.jpg' || ext == '.jpeg' || ext == '.webp')
        ? ext
        : '.jpg';
    final target = File(p.join(dir.path, 'avatar$safeExt'));
    await source.copy(target.path);

    // Limpia avatar anterior con otra extensión.
    if (_avatarPath != null &&
        _avatarPath != target.path &&
        File(_avatarPath!).existsSync()) {
      try {
        await File(_avatarPath!).delete();
      } catch (_) {}
    }

    _avatarPath = target.path;
    notifyListeners();
    await PreferencesService.setProfileAvatarPath(target.path);
  }

  Future<void> clearAvatar() async {
    if (_avatarPath != null) {
      try {
        final file = File(_avatarPath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
    _avatarPath = null;
    notifyListeners();
    await PreferencesService.setProfileAvatarPath(null);
  }
}
