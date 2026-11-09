import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/services/content_exclusions.dart';

void main() {
  test('merges IDs and reuses them until the cache expires', () async {
    var time = DateTime.utc(2026, 11, 3);
    final calls = <String>[];
    final cache = ExcludedContentIds(
      now: () => time,
      loadIndex: (token) async {
        calls.add(token);
        return token.startsWith('female:') ? [1, 2, 2] : [2, 3];
      },
    );
    final first = await cache.load();
    expect(first, {1, 2, 3});
    expect(calls.toSet(), ContentExclusions.indexTokens.toSet());
    final firstCallCount = calls.length;
    time = time.add(const Duration(minutes: 9));
    expect(await cache.load(), same(first));
    expect(calls, hasLength(firstCallCount));
    time = time.add(const Duration(minutes: 2));
    expect(await cache.load(), {1, 2, 3});
    expect(calls, hasLength(firstCallCount * 2));
    expect(() => first.add(99), throwsUnsupportedError);
  });

  test('simultaneous readers share one pending index load', () async {
    final gate = Completer<void>();
    var calls = 0;
    final cache = ExcludedContentIds(
      loadIndex: (_) async {
        calls++;
        await gate.future;
        return [1];
      },
    );
    final first = cache.load();
    final second = cache.load();
    expect(second, same(first));
    gate.complete();
    expect(await first, {1});
    expect(await second, {1});
    expect(calls, ContentExclusions.indexTokens.length);
  });

  test('bounds index concurrency as the exclusion list grows', () async {
    var active = 0;
    var maximum = 0;
    final cache = ExcludedContentIds(
      loadIndex: (_) async {
        active++;
        if (active > maximum) maximum = active;
        await Future<void>.value();
        active--;
        return [];
      },
    );
    expect(await cache.load(), isEmpty);
    expect(maximum, inInclusiveRange(2, 4));
    expect(active, 0);
  });

  test(
    'a failed index is reported and does not cache an incomplete result',
    () async {
      var failNext = true;
      final cache = ExcludedContentIds(
        loadIndex: (_) async {
          if (failNext) {
            failNext = false;
            throw StateError('synthetic index failure');
          }
          return [2];
        },
      );
      await expectLater(cache.load(), throwsStateError);
      expect(await cache.load(), {2});
    },
  );

  test(
    'clearing during a load prevents the old result replacing the new cache',
    () async {
      final oldGate = Completer<void>();
      var old = true;
      final cache = ExcludedContentIds(
        loadIndex: (_) async {
          final isOld = old;
          if (isOld) await oldGate.future;
          return [isOld ? 1 : 2];
        },
      );
      final first = cache.load();
      old = false;
      cache.clear();
      final fresh = await cache.load();
      expect(fresh, {2});
      oldGate.complete();
      expect(await first, contains(1));
      expect(await cache.load(), same(fresh));
    },
  );
}
