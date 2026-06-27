import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sembast/sembast.dart';

import 'package:time_machine_db/time_machine_db.dart';

void main() {
  group('Repository create()', () {
    Future<Database> freshDb(String name) async {
      return databaseFactoryMemory.openDatabase('test_create_${name}_${DateTime.now().millisecondsSinceEpoch}.db');
    }

    test('creates Picture repository', () async {
      final db = await freshDb('pic');
      final repo = Repository<Picture>.create(db: db);
      expect(repo, isA<Repository<Picture>>());
    });

    test('creates Record repository', () async {
      final db = await freshDb('rec');
      final repo = Repository<Record>.create(db: db);
      expect(repo, isA<Repository<Record>>());
    });

    test('throws for unsupported type', () async {
      final db = await freshDb('int');
      expect(
        () => Repository<int>.create(db: db),
        throwsException,
      );
    });
  });
}
