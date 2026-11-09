/// Secretos de integraciones. Nunca hardcodear claves en el APK.
///
/// Pasarlas en compile-time:
/// `flutter build apk --dart-define=MAL_CLIENT_ID=... --dart-define=MAL_CLIENT_SECRET=...`
class AppSecrets {
  static const malClientId = String.fromEnvironment('MAL_CLIENT_ID');
  static const malClientSecret = String.fromEnvironment('MAL_CLIENT_SECRET');

  static bool get hasMalCredentials =>
      malClientId.isNotEmpty && malClientSecret.isNotEmpty;
}
