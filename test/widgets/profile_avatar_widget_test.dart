import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/models/content_identity.dart';
import 'package:yomashi/providers/profile_provider.dart';
import 'package:yomashi/services/image_repository.dart';
import 'package:yomashi/widgets/profile_avatar.dart';

import 'profile_myanimelist_test.dart'
    show DelayedProfileCredential, OfflineProfileMal, connectedIdentity;

void main() {
  const picture = 'https://cdn.myanimelist.net/images/userimages/7.jpg?t=1';
  for (final cacheAvailable in [true, false]) {
    testWidgets('MAL avatar uses cache=$cacheAvailable and retains local fallback', (
      tester,
    ) async {
      final folder = Directory.systemTemp.createTempSync('yomashi-avatar-');
      final tempRoot = Directory.systemTemp.resolveSymbolicLinksSync();
      final resolvedFolder = folder.resolveSymbolicLinksSync();
      if (!p.isWithin(tempRoot, resolvedFolder) ||
          !p.basename(resolvedFolder).startsWith('yomashi-avatar-')) {
        throw StateError(
          'Avatar fixture must stay inside the temporary directory',
        );
      }
      final local = File(p.join(folder.path, 'local.png'));
      final cached = File(
        p.join(folder.path, '${ContentIdentity.id(picture)}.image'),
      );
      final png = img.encodePng(img.Image(width: 2, height: 2));
      local.writeAsBytesSync(png);
      cached.writeAsBytesSync(png);
      final repository = ImageRepository.shared;
      final previousDirectory = repository.cacheDirectory;
      if (cacheAvailable) {
        repository.cacheDirectory = folder;
      } else {
        final unavailable = File(p.join(folder.path, 'unavailable'));
        unavailable.writeAsStringSync('not a directory');
        repository.cacheDirectory = Directory(unavailable.path);
      }
      SharedPreferences.setMockInitialValues({
        'profile_avatar_path_v1': local.path,
      });
      final credentials = DelayedProfileCredential()
        ..value = connectedIdentity(7, 'MangaReader', picture: picture);
      final client = OfflineProfileMal(credentials)..offline = true;
      final profile = ProfileProvider(malClient: client);

      File? displayedFile() {
        final images = find.byType(Image);
        if (images.evaluate().length != 1) return null;
        final image = tester.widget<Image>(images).image;
        final original = image is ResizeImage ? image.imageProvider : image;
        return original is FileImage ? original.file : null;
      }

      Future<void> waitForFile(File expected) async {
        // Each iteration gives the real file system and image codec a turn;
        // pumpAndSettle alone only advances the fake widget-test clock.
        for (var attempt = 0; attempt < 100; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
          final displayed = displayedFile();
          if (displayed != null && p.equals(displayed.path, expected.path)) {
            final pixels = find.descendant(
              of: find.byType(Image),
              matching: find.byType(RawImage),
            );
            if (pixels.evaluate().length != 1 ||
                tester.widget<RawImage>(pixels).image == null) {
              continue;
            }
            expect(p.equals(displayedFile()!.path, expected.path), isTrue);
            return;
          }
        }
        fail(
          'Expected avatar ${expected.path}, displayed ${displayedFile()?.path}',
        );
      }

      try {
        // Preflight the same repository without networking and outside the fake
        // clock. The widget still resolves the real cache on its own afterwards.
        if (cacheAvailable) {
          final resolved = await tester.runAsync(
            () => repository.resolve(picture),
          );
          expect(p.equals(resolved!.path, cached.path), isTrue);
        }
        await profile.load();
        await profile.refreshMyAnimeList();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AnimatedBuilder(
                animation: profile,
                builder: (_, _) => ProfileAvatar(profile: profile),
              ),
            ),
          ),
        );
        await waitForFile(cacheAvailable ? cached : local);
        expect(find.bySemanticsLabel('Foto de MyAnimeList'), findsOneWidget);
        await credentials.clear();
        await profile.reloadMyAnimeListIdentity();
        await tester.pump();
        await waitForFile(local);
        expect(find.bySemanticsLabel('Foto de perfil'), findsOneWidget);
        expect(local.existsSync(), isTrue);
        expect(
          (await SharedPreferences.getInstance()).getString(
            'profile_avatar_path_v1',
          ),
          local.path,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        profile.dispose();
        client.sessionChanges.dispose();
        client.http.close(force: true);
        repository.cacheDirectory = previousDirectory;
        await tester.runAsync(() async {
          // Finish file-image reads and cache metadata touches before deleting
          // the verified test-owned directory, including Windows file handles.
          for (var attempt = 0; attempt < 20; attempt++) {
            await Future<void>.delayed(const Duration(milliseconds: 25));
            try {
              if (await folder.exists()) await folder.delete(recursive: true);
              return;
            } on FileSystemException {
              if (attempt == 19) rethrow;
            }
          }
        });
      }
    });
  }
}
