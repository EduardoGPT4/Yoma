import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'failed initialization can be retried with an available database',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      SharedPreferences.setMockInitialValues({});
      final unavailable = AppDatabase.forTesting(
        LazyDatabase(() async => throw StateError('unavailable')),
      );
      await expectLater(
        LibraryStore.initialize(database: unavailable),
        throwsStateError,
      );
      final store = await LibraryStore.initialize(
        database: AppDatabase.forTesting(NativeDatabase.memory()),
      );
      await store.putRecord('test', 'record', {'value': 1});
      expect((await store.getRecord('test', 'record'))['value'], 1);
    },
  );
}
