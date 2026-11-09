import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/services/myanimelist_client.dart';
import '../services/download_engine_regression_test.dart' show RealHttp;
import '../widgets/myanimelist_test.dart' show MemoryCredential;

// Opt-in: creates and revokes its own pending device connection on the real
// backend. It does not authorize a MAL account or change anybody's manga list.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real backend accepts Dart handshake, pairs and revokes the device',
    () async {
      final raw = HttpOverrides.runWithHttpOverrides(
        () => HttpClient(),
        RealHttp(),
      );
      final store = MemoryCredential()..value = null;
      final client = MyAnimeListClient(
        http: raw,
        credentials: store,
        solveHostCookie: (values) async {
          // Same AES-CBC operation as the native Android bridge, using the
          // local PHP runtime so this host-side test needs no Android device.
          final process = await Process.start('php', [
            '-r',
            r'$v=json_decode(stream_get_contents(STDIN),true);echo bin2hex(openssl_decrypt(hex2bin($v[2]),"aes-128-cbc",hex2bin($v[0]),OPENSSL_RAW_DATA|OPENSSL_ZERO_PADDING,hex2bin($v[1])));',
          ]);
          process.stdin.write(jsonEncode(values));
          await process.stdin.close();
          final result = await utf8.decoder.bind(process.stdout).join();
          expect(await process.exitCode, 0);
          return result.trim();
        },
      );
      try {
        final pair = await client.begin();
        expect(pair['code'], isA<String>());
        expect((await client.account())!['connected'], false);
        await expectLater(
          client.detail(2),
          throwsA(isA<MalFailure>().having((e) => e.status, 'status', 409)),
        );
        final pending = Map<String, dynamic>.from(store.value!);
        await client.disconnect();
        expect(store.value, isNull);
        await store.save(pending);
        await expectLater(
          client.account(),
          throwsA(isA<MalFailure>().having((e) => e.status, 'status', 401)),
        );
        expect(store.value, isNull);
      } finally {
        if (store.value != null) await client.disconnect();
        raw.close(force: true);
      }
    },
    skip: !const bool.fromEnvironment('YOMASHI_LIVE_MAL'),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
