import 'dart:ui';

class TranslationBlock {
  final Rect bounds;
  final String original, translated;

  const TranslationBlock({
    required this.bounds,
    required this.original,
    required this.translated,
  });

  factory TranslationBlock.fromMap(Map<Object?, Object?> map) =>
      TranslationBlock(
        bounds: Rect.fromLTWH(
          (map['left'] as num).toDouble(),
          (map['top'] as num).toDouble(),
          (map['width'] as num).toDouble(),
          (map['height'] as num).toDouble(),
        ),
        original: map['original'] as String,
        translated: map['translated'] as String,
      );
}

class PageTranslation {
  final String url, sourceLanguage, targetLanguage, imagePath;
  final List<TranslationBlock> blocks;
  final int textOnlyBlocks;

  const PageTranslation({
    required this.url,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.imagePath,
    required this.blocks,
    required this.textOnlyBlocks,
  });
}

const translationLanguages = {
  'ja': 'Japonés',
  'zh': 'Chino',
  'ko': 'Coreano',
  'en': 'Inglés',
  'es': 'Español',
  'pt': 'Portugués',
  'fr': 'Francés',
  'de': 'Alemán',
  'it': 'Italiano',
};
