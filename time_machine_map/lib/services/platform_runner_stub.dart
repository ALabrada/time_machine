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
}) async {
  final bytes = await renderTileToBytes(
    z: z, x: x, y: y, zoom: zoom, style: style,
  );
  return XFile.fromData(bytes, name: 'tile_${z}_${x}_$y.png');
}
