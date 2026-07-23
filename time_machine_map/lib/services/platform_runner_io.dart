import 'dart:io';
import 'dart:isolate';

import 'package:cross_file/cross_file.dart';

import '../domain/vector_tile_style.dart';
import 'tile_renderer.dart';

Future<XFile> renderTileOffThread({
  required int z,
  required int x,
  required int y,
  required double zoom,
  required VectorTileStyle style,
  required String? outputPath,
}) {
  return Isolate.run(() async {
    final bytes = await renderTileToBytes(
      z: z, x: x, y: y, zoom: zoom, style: style,
    );
    await File(outputPath!).writeAsBytes(bytes);
    return XFile(outputPath);
  });
}
