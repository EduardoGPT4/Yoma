import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final original = img.decodePng(
    File('assets/branding/1-Anime.png').readAsBytesSync(),
  )!;
  final small = img.encodePng(img.copyResize(original, width: 256));
  File('android/app/src/main/assets/anime-brand.png').writeAsBytesSync(small);
  File(
    'android/app/src/main/res/drawable-nodpi/anime_brand.png',
  ).writeAsBytesSync(small);
}
