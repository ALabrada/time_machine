import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';

dynamic _patchUnsupported(dynamic node) {
  if (node is List) {
    if (node.isNotEmpty && node[0] == 'boolean' && node.length == 3) {
      return _patchUnsupported(node[1]);
    }
    if (node.isNotEmpty && node[0] == 'feature-state' && node.length == 2) {
      return ['get', _patchUnsupported(node[1])];
    }
    return node.map(_patchUnsupported).toList(growable: false);
  }
  if (node is Map) {
    return node.map((k, v) => MapEntry(k, _patchUnsupported(v)));
  }
  return node;
}

void main() {
  test('parse main_style.json with ThemeReader (patched)', () {
    final file = File('test/assets/main_style.json');
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

    final layers = json['layers'] as List<dynamic>;
    final symbolRaw = layers.where((l) => l is Map && l['type'] == 'symbol').length;
    print('Raw JSON: ${layers.length} total layers, $symbolRaw symbol');

    // Apply our readTheme patch
    final patched = Map<String, dynamic>.from(json);
    patched['layers'] = (patched['layers'] as List<dynamic>).map((layer) {
      final p = _patchUnsupported(layer);
      if (p is Map<String, dynamic> &&
          p['type'] == 'symbol' &&
          p['paint'] == null) {
        p['paint'] = <String, dynamic>{};
      }
      return p;
    }).toList(growable: false);

    final reader = ThemeReader(logger: Logger.console());
    final theme = reader.read(patched);

    final symbols = theme.layers.where((l) => l.type == ThemeLayerType.symbol).toList();
    print('Parsed theme: ${theme.layers.length} total, ${symbols.length} symbol');

    final symbolIds = symbols.map((l) => l.id).toSet();
    for (final sl in layers.where((l) => l is Map && l['type'] == 'symbol')) {
      final id = sl['id'] as String;
      if (symbolIds.contains(id)) {
        print('  SURVIVED: "$id"');
      } else {
        print('  DROPPED:  "$id"');
      }
    }
  });
}
