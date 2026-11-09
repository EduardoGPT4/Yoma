import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yomashi/models/ui_density.dart';
import 'package:yomashi/providers/density_provider.dart';
import 'package:yomashi/widgets/manga_card.dart';

class _FixedDensity extends DensityProvider {
  final UiDensity value;
  _FixedDensity(this.value);
  @override
  UiDensity get density => value;
}

void main() {
  for (final width in [320.0, 1220 / 3]) {
    for (final scale in [0.9, 2.0]) {
      for (final density in UiDensity.values) {
        testWidgets('long titles fit at $width, $scale, ${density.name}', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          MangaCard card() => MangaCard(
            title: 'Boku no Hero Academia y un título muy largo',
            coverPath: null,
            onTap: () {},
          );

          await tester.pumpWidget(
            ChangeNotifierProvider<DensityProvider>(
              create: (_) => _FixedDensity(density),
              child: MaterialApp(
                home: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 1000),
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: Scaffold(
                    body: Builder(
                      builder: (context) => Column(
                        children: [
                          SizedBox(
                            height: MangaCardLayout.heightForWidth(
                              context,
                              120,
                            ),
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [SizedBox(width: 120, child: card())],
                            ),
                          ),
                          Expanded(
                            child: CustomScrollView(
                              slivers: [
                                SliverPadding(
                                  padding: const EdgeInsets.all(12),
                                  sliver: SliverMangaGrid(
                                    delegate: SliverChildListDelegate([
                                      card(),
                                      card(),
                                      card(),
                                    ]),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.byType(MangaCard), findsNWidgets(4));
        });
      }
    }
  }
}
