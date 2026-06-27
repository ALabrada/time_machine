import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sembast/sembast.dart';

import 'package:time_machine_db/time_machine_db.dart';

void main() {
  group('DatabaseService', () {
    test('expandPath replaces placeholder', () async {
      final db = await databaseFactoryMemory.openDatabase('test_db_1.db');
      final service = DatabaseService(db: db, dataPath: '/data/path');
      final expanded = service.expandPath('/[FILES]/photos/img.jpg');
      expect(expanded, '/data/path/files/photos/img.jpg');
    });

    test('expandPath returns original when dataPath is null', () async {
      final db = await databaseFactoryMemory.openDatabase('test_db_2.db');
      final service = DatabaseService(db: db);
      final expanded = service.expandPath('/some/path/file.txt');
      expect(expanded, '/some/path/file.txt');
    });

    test('filePath returns dataPath/files', () async {
      final db = await databaseFactoryMemory.openDatabase('test_db_3.db');
      final service = DatabaseService(db: db, dataPath: '/root');
      expect(service.filePath, '/root/files');
    });

    test('filePath returns null when dataPath is null', () async {
      final db = await databaseFactoryMemory.openDatabase('test_db_4.db');
      final service = DatabaseService(db: db);
      expect(service.filePath, isNull);
    });

    test('createRepository creates Picture repository', () async {
      final db = await databaseFactoryMemory.openDatabase('test_db_5.db');
      final service = DatabaseService(db: db);
      final repo = service.createRepository<Picture>();
      expect(repo, isA<Repository<Picture>>());
    });

    test('createRepository creates Record repository', () async {
      final db = await databaseFactoryMemory.openDatabase('test_db_6.db');
      final service = DatabaseService(db: db);
      final repo = service.createRepository<Record>();
      expect(repo, isA<Repository<Record>>());
    });
  });
}
