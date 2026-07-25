import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:time_machine_map/domain/vector_tile_style.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';

// ---------------------------------------------------------------
// Inline a copy of the patching logic so the test can inspect the
// intermediate JSON before it reaches ThemeReader.
// ---------------------------------------------------------------

dynamic _patchUnsupported(dynamic node) {
  if (node is List) {
    if (node.isNotEmpty && node[0] == 'boolean' && node.length == 3) {
      return _patchUnsupported(node[1]);
    }
    if (node.isNotEmpty && node[0] == 'feature-state' && node.length == 2) {
      return ['get', _patchUnsupported(node[1])];
    }
    if (node.length >= 4 &&
        node[0] == 'interpolate' &&
        node[1] is List &&
        node[1].length >= 2 &&
        node[1][0] == 'exponential' &&
        _hasColorOutputs(node)) {
      final patched = [...node];
      patched[1] = ['linear'];
      return patched.map(_patchUnsupported).toList(growable: false);
    }
    return node.map(_patchUnsupported).toList(growable: false);
  }
  if (node is Map) {
    return node.map((k, v) => MapEntry(k, _patchUnsupported(v)));
  }
  return node;
}

bool _hasColorOutputs(List node) {
  for (int i = 3; i + 1 < node.length; i += 2) {
    final output = node[i + 1];
    if (output is String && _isColorString(output)) return true;
  }
  return false;
}

bool _isColorString(String s) {
  return s.startsWith('#') || s.startsWith('rgb') || s.startsWith('hsl');
}

// ---------------------------------------------------------------
// Walk helpers
// ---------------------------------------------------------------

/// Recursively visit every node in the JSON tree and call [visit]
/// with the path (list of keys/indices).
void _walk(dynamic node, List<Object> path, void Function(List<Object>, dynamic) visit) {
  visit(path, node);
  if (node is List) {
    for (int i = 0; i < node.length; i++) {
      _walk(node[i], [...path, i], visit);
    }
  } else if (node is Map) {
    node.forEach((k, v) => _walk(v, [...path, k], visit));
  }
}

// ---------------------------------------------------------------

void main() {
  final styleFile = File('test/assets/main_style.json');
  if (!styleFile.existsSync()) {
    print('Skipping – main_style.json not found');
    return;
  }

  final rawJson = jsonDecode(styleFile.readAsStringSync()) as Map<String, dynamic>;
  final layers = (rawJson['layers'] as List<dynamic>).cast<Map<String, dynamic>>();

  group('color interpolation (exponential → linear)', () {
    // --- Pre-patch scan --------------------------------------------------
    late List<Map<String, Object>> expColorNodes;

    setUp(() {
      expColorNodes = [];
      for (final layer in layers) {
        _walk(layer, [layer['id']], (path, node) {
          if (node is List &&
              node.length >= 4 &&
              node[0] == 'interpolate' &&
              node[1] is List &&
              (node[1] as List).isNotEmpty &&
              (node[1] as List)[0] == 'exponential' &&
              _hasColorOutputs(node)) {
            expColorNodes.add({
              'path': path.join('.'),
              'layer': path.first,
              'preview': node.sublist(0, 4),
            });
          }
        });
      }
    });

    test('style has exponential color interpolations that need fixing', () {
      // Sanity check – there should be several.
      // If the style changes and this drops to 0, the test below is vacuously true.
      print('Found ${expColorNodes.length} exponential color interpolations');
      for (final n in expColorNodes) {
        print('  ${n['layer']}: ${n['preview']}');
      }
      expect(expColorNodes.length, greaterThan(0),
          reason: 'Expected at least one exponential color interpolation');
    });

    test('patched JSON has zero exponential color interpolations', () {
      // Apply the same patches that readTheme() uses.
      final patchedLayers = layers.map((layer) {
        var patched = _patchUnsupported(layer);
        if (patched is Map<String, dynamic>) {
          if (patched['type'] == 'fill' && patched['paint'] is Map) {
            final paint = patched['paint'] as Map;
            if (paint['fill-outline-color'] != null &&
                paint['fill-outline-width'] == null) {
              paint['fill-outline-width'] = 16;
            }
          }
        }
        return patched;
      }).toList();

      // Count remaining exponential color interpolations.
      final remaining = <String>[];
      for (final layer in patchedLayers) {
        final id = layer is Map ? layer['id'] ?? '<unknown>' : '<unknown>';
        _walk(layer, [id], (path, node) {
          if (node is List &&
              node.length >= 4 &&
              node[0] == 'interpolate' &&
              node[1] is List &&
              (node[1] as List).isNotEmpty &&
              (node[1] as List)[0] == 'exponential' &&
              _hasColorOutputs(node)) {
            remaining.add('$id: ${path.join('.')}');
          }
        });
      }

      if (remaining.isNotEmpty) {
        print('Remaining exponential color interpolations:');
        for (final r in remaining) {
          print('  $r');
        }
      }
      expect(remaining, isEmpty,
          reason: 'All exponential color interpolations should be converted to linear');
    });

    test('all converted interpolations now use ["linear"]', () {
      final patchedLayers = layers.map((layer) => _patchUnsupported(layer)).toList();

      int linearColorCount = 0;
      int anyNonLinear = 0;
      for (final layer in patchedLayers) {
        _walk(layer, [], (path, node) {
          if (node is List &&
              node.length >= 4 &&
              node[0] == 'interpolate' &&
              _hasColorOutputs(node)) {
            if (node[1] is List &&
                (node[1] as List).isNotEmpty &&
                (node[1] as List)[0] == 'linear') {
              linearColorCount++;
            } else {
              anyNonLinear++;
            }
          }
        });
      }

      expect(linearColorCount, greaterThan(0),
          reason: 'Expected at least one linear color interpolation after patching');
      expect(anyNonLinear, 0,
          reason: 'No color interpolation should use a non-linear type after patching');
    });

    test('exponential interpolation with literal-color outputs is fully eliminated', () {
      // Non-color non-numeric outputs (expressions that eval to numbers,
      // arrays for offsets/dashes) are intentionally left as exponential —
      // they either resolve to numerics at eval time or aren't color-related.
      final patchedLayers = layers.map((layer) => _patchUnsupported(layer)).toList();

      final remainingColor = <String>[];
      for (final layer in patchedLayers) {
        final id = layer is Map ? layer['id'] ?? '<unknown>' : '<unknown>';
        _walk(layer, [], (path, node) {
          if (node is List &&
              node.length >= 4 &&
              node[0] == 'interpolate' &&
              node[1] is List &&
              (node[1] as List).isNotEmpty &&
              (node[1] as List)[0] == 'exponential' &&
              _hasColorOutputs(node)) {
            remainingColor.add('$id: ${path.join('.')}');
          }
        });
      }
      expect(remainingColor, isEmpty,
          reason: 'Every exponential interpolation with literal color outputs must be converted to linear');
    });
  });

  group('fill-outline-width fix', () {
    test('every fill layer with outline-color gets a visible outline width', () {
      final patchedLayers = layers.map((layer) {
        var patched = _patchUnsupported(layer);
        if (patched is Map<String, dynamic>) {
          if (patched['type'] == 'fill' && patched['paint'] is Map) {
            final paint = patched['paint'] as Map;
            if (paint['fill-outline-color'] != null &&
                paint['fill-outline-width'] == null) {
              paint['fill-outline-width'] = 16;
            }
          }
        }
        return patched;
      }).toList();

      for (final layer in patchedLayers) {
        if (layer is! Map<String, dynamic>) continue;
        if (layer['type'] != 'fill') continue;
        final paint = layer['paint'];
        if (paint is! Map) continue;

        if (paint['fill-outline-color'] != null) {
          final id = layer['id'] ?? '<unknown>';
          expect(paint['fill-outline-width'], isNotNull,
              reason: 'Fill layer "$id" has fill-outline-color but no fill-outline-width');
          expect(paint['fill-outline-width'], equals(16),
              reason: 'Fill layer "$id" should have fill-outline-width=16 (1px)');
        }
      }
    });
  });

  group('full round-trip through readTheme()', () {
    test('readTheme() produces theme with all expected fill layers', () {
      final style = VectorTileStyle(
        theme: rawJson,
        sources: {},
      );
      final theme = style.readTheme();

      final fillLayerIds = theme.layers
          .where((l) => l.type == ThemeLayerType.fill)
          .map((l) => l.id)
          .toSet();

      // These are the fill layers from main_style.json that should survive.
      // If any is missing, the patching may have dropped it.
      final expected = {
        'landuse education',
        'landcover wood',
        'landcover farmland',
        'landcover scrub',
        'landcover wetland',
        'landcover sand',
        'landcover glacier',
        'landuse cemetery',
        'landuse industrial',
        'landuse hospital',
        'landuse parking',
        'pedestrian area',
        'pier area',
        'aerodrome',
        'landcover grass',
        'water',
        'building background',
        'building',
        'pitch',
        'running_track',
      };

      for (final id in expected) {
        expect(fillLayerIds.contains(id), isTrue,
            reason: 'Expected fill layer "$id" to be present in parsed theme');
      }

      print('Fill layers in parsed theme (${fillLayerIds.length}):');
      for (final id in fillLayerIds.toList()..sort()) {
        print('  $id');
      }
    });
  });
}
