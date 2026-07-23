import 'package:flutter_test/flutter_test.dart';

import 'package:time_machine_map/time_machine_map.dart';

void main() {
  test('package exports TileCachingService', () {
    expect(TileCachingService, isA<Type>());
  });

  test('package exports VectorService', () {
    expect(VectorService, isA<Type>());
  });

  test('package exports TileRenderCanceller', () {
    expect(TileRenderCanceller, isA<Type>());
  });

  test('package exports MapPage', () {
    expect(MapPage, isA<Type>());
  });
}
