import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/providers/source_provider.dart';
import 'package:yomashi/services/mangadex_service.dart';
import 'package:yomashi/utils/preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MangaDexService.setPreferredLanguages(MangaDexLanguage.defaultCodes);
  });

  tearDown(() {
    MangaDexService.setPreferredLanguages(MangaDexLanguage.defaultCodes);
  });

  test('offers multiple chapter languages and regional MangaDex codes', () {
    final codes = MangaDexLanguage.selectable.map((language) => language.code);
    expect(
      codes,
      containsAll([
        'es',
        'es-la',
        'en',
        'ja',
        'ko',
        'zh',
        'zh-hk',
        'pt',
        'pt-br',
        'fr',
        'de',
        'it',
        'ru',
        'ar',
        'vi',
        'id',
        'th',
      ]),
    );
    expect(codes.toSet(), hasLength(codes.length));
    expect(MangaDexLanguage.defaultCodes, ['es', 'es-la']);
  });

  test(
    'normalizes restored languages consistently in provider and API',
    () async {
      SharedPreferences.setMockInitialValues({
        'mangadex_languages_v1': [' EN ', 'en', 'pt-BR', '', 'not-a-language'],
      });
      final provider = SourceProvider();
      addTearDown(provider.dispose);
      await provider.load();

      expect(provider.mangaDexLanguages, ['en', 'pt-br']);
      expect(MangaDexService.preferredLanguages, provider.mangaDexLanguages);
    },
  );

  test(
    'invalid restored languages fall back to the existing Spanish defaults',
    () async {
      SharedPreferences.setMockInitialValues({
        'mangadex_languages_v1': ['', 'not-a-language'],
      });
      final provider = SourceProvider();
      addTearDown(provider.dispose);
      await provider.load();

      expect(provider.mangaDexLanguages, ['es', 'es-la']);
      expect(MangaDexService.preferredLanguages, ['es', 'es-la']);
    },
  );

  test(
    'language selection persists and cannot deselect the last language',
    () async {
      final provider = SourceProvider();
      addTearDown(provider.dispose);
      await provider.load();
      await provider.toggleMangaDexLanguage('en');
      await provider.toggleMangaDexLanguage('pt-br');
      await provider.toggleMangaDexLanguage('es');
      await provider.toggleMangaDexLanguage('es-la');
      expect(provider.mangaDexLanguages, ['en', 'pt-br']);
      expect(await PreferencesService.getMangaDexLanguages(), ['en', 'pt-br']);

      final restored = SourceProvider();
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.mangaDexLanguages, ['en', 'pt-br']);
      await restored.toggleMangaDexLanguage('pt-br');
      await restored.toggleMangaDexLanguage('en');
      expect(restored.mangaDexLanguages, ['en']);
      expect(MangaDexService.preferredLanguages, ['en']);
      expect(await PreferencesService.getMangaDexLanguages(), ['en']);
    },
  );

  test(
    'ignores unsupported toggles without saving an invalid API filter',
    () async {
      final provider = SourceProvider();
      addTearDown(provider.dispose);
      await provider.load();
      await provider.toggleMangaDexLanguage('not-a-language');
      expect(provider.mangaDexLanguages, ['es', 'es-la']);
      expect(MangaDexService.preferredLanguages, ['es', 'es-la']);
    },
  );
}
