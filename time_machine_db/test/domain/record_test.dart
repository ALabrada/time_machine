import 'package:flutter_test/flutter_test.dart';

import 'package:time_machine_db/time_machine_db.dart';

void main() {
  group('Record', () {
    final now = DateTime(2024, 6, 15, 12, 0, 0);

    Record createSampleRecord({
      int? localId,
      int? originalId,
      String? originalViewPort,
      String? pictureViewPort,
      double? height,
      double? width,
    }) {
      return Record(
        pictureId: 1,
        createdAt: now,
        updateAt: now,
        visitedAt: now,
        localId: localId,
        originalId: originalId,
        height: height ?? 1080.0,
        width: width ?? 1920.0,
        originalViewPort: originalViewPort,
        pictureViewPort: pictureViewPort,
      );
    }

    test('fromJson creates Record correctly', () {
      final json = {
        'pictureId': 1,
        'createdAt': now.millisecondsSinceEpoch,
        'updateAt': now.millisecondsSinceEpoch,
        'visitedAt': now.millisecondsSinceEpoch,
        'originalId': 5,
        'height': 1080.0,
        'width': 1920.0,
        'originalViewPort': '0,0,800,600',
        'pictureViewPort': '100,50,1920,1080',
      };
      final record = Record.fromJson(json);
      expect(record.pictureId, 1);
      expect(record.createdAt, now);
      expect(record.updateAt, now);
      expect(record.visitedAt, now);
      expect(record.originalId, 5);
      expect(record.height, 1080.0);
      expect(record.width, 1920.0);
    });

    test('fromJson handles null fields', () {
      final json = {
        'pictureId': 2,
        'createdAt': now.millisecondsSinceEpoch,
        'updateAt': now.millisecondsSinceEpoch,
      };
      final record = Record.fromJson(json);
      expect(record.pictureId, 2);
      expect(record.visitedAt, isNull);
      expect(record.originalId, isNull);
      expect(record.height, isNull);
    });

    test('toJson returns correct map', () {
      final record = createSampleRecord();
      final json = record.toJson();
      expect(json['pictureId'], 1);
      expect(json['createdAt'], now.millisecondsSinceEpoch);
      expect(json['updateAt'], now.millisecondsSinceEpoch);
      expect(json['visitedAt'], now.millisecondsSinceEpoch);
    });

    test('tryParseViewPort parses valid string', () {
      final rect = Record.tryParseViewPort('0,0,800,600');
      expect(rect, isNotNull);
      expect(rect!.left, 0);
      expect(rect.top, 0);
      expect(rect.width, 800);
      expect(rect.height, 600);
    });

    test('tryParseViewPort parses semicolon separated', () {
      final rect = Record.tryParseViewPort('10;20;300;400');
      expect(rect, isNotNull);
      expect(rect!.left, 10);
      expect(rect.top, 20);
      expect(rect.width, 300);
      expect(rect.height, 400);
    });

    test('tryParseViewPort returns null for invalid string', () {
      expect(Record.tryParseViewPort(null), isNull);
      expect(Record.tryParseViewPort(''), isNull);
      expect(Record.tryParseViewPort('1,2,3'), isNull);
      expect(Record.tryParseViewPort('a,b,c,d'), isNull);
    });

    test('originalAspectRatio returns correct value', () {
      final record = createSampleRecord(originalViewPort: '0,0,800,600');
      expect(record.originalAspectRatio, closeTo(800 / 600, 0.001));
    });

    test('originalAspectRatio returns null when no viewport', () {
      final record = createSampleRecord();
      expect(record.originalAspectRatio, isNull);
    });

    test('pictureAspectRatio returns correct value', () {
      final record = createSampleRecord(pictureViewPort: '0,0,1600,900');
      expect(record.pictureAspectRatio, closeTo(1600 / 900, 0.001));
    });

    test('aspectRatio uses max viewport dimensions', () {
      final record = createSampleRecord(
        originalViewPort: '0,0,800,600',
        pictureViewPort: '0,0,1600,900',
      );
      expect(record.aspectRatio, closeTo(1600 / 900, 0.001));
    });

    test('aspectRatio falls back to width/height when no viewports', () {
      final record = createSampleRecord(height: 1080, width: 1920);
      expect(record.aspectRatio, closeTo(1920 / 1080, 0.001));
    });

    test('aspectRatio returns null when no dimensions available', () {
      final record = createSampleRecord();
      record.height = null;
      record.width = null;
      expect(record.aspectRatio, isNull);
    });

    test('roundtrip preserves values', () {
      final original = createSampleRecord(
        originalViewPort: '0,0,800,600',
        pictureViewPort: '100,50,1920,1080',
      );
      final json = original.toJson();
      final restored = Record.fromJson(json);
      expect(restored.pictureId, original.pictureId);
      expect(restored.createdAt, original.createdAt);
      expect(restored.updateAt, original.updateAt);
      expect(restored.visitedAt, original.visitedAt);
      expect(restored.height, original.height);
      expect(restored.width, original.width);
    });
  });
}
