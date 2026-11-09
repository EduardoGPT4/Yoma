import 'dart:convert';
import '../data/library_store.dart';
import '../utils/app_failure.dart';

/// Registro acotado; nunca almacena cabeceras, cuerpos ni consultas de URLs.
class Diagnostics {
  static final List<Map<String, dynamic>> _memory = [];
  static Future<void> record(String component, Object error) async {
    if (error is AppFailure && error.kind == FailureKind.cancelled) return;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final entry = <String, dynamic>{
      'id': id,
      'time': DateTime.now().toIso8601String(),
      'component': component,
      'kind': error is AppFailure
          ? error.kind.name
          : error.runtimeType.toString(),
      'status': error is AppFailure ? error.statusCode : null,
      'message': error
          .toString()
          .replaceAll(RegExp(r'https?://[^\s]+'), '[URL]')
          .substring(
            0,
            error
                .toString()
                .replaceAll(RegExp(r'https?://[^\s]+'), '[URL]')
                .length
                .clamp(0, 500),
          ),
    };
    _memory.add(entry);
    if (_memory.length > 100) _memory.removeAt(0);
    final store = LibraryStore.current;
    if (store == null) return;
    try {
      await store.putRecord('diagnostics', id, entry);
      final rows = await store.readRecords('diagnostics');
      if (rows.length > 100) {
        await store.replaceRecords(
          'diagnostics',
          rows.skip(rows.length - 100).toList(),
        );
      }
    } catch (_) {
      /* El registro no debe sustituir el error original. */
    }
  }

  static Future<String> export() async {
    final store = LibraryStore.current;
    final entries = store == null
        ? _memory
        : await store.readRecords('diagnostics');
    return const JsonEncoder.withIndent(
      '  ',
    ).convert({'version': 1, 'events': entries});
  }
}
