import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final dir = await Directory(
      'build/integration_reports',
    ).create(recursive: true);
    final name = Platform.environment['YOMASHI_REPORT_NAME'] ?? 'device';
    await File(
      '${dir.path}/$name.json',
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  },
);
