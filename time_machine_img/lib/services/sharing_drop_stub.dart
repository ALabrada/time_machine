import 'dart:typed_data';

/// No-op implementation for non-web targets. On desktop the drop-in import is
/// folder based and lives entirely in [SharingService]; on mobile it is
/// intent based. Only the web build registers browser drag-and-drop handlers.
final class SharingDropIn {
  SharingDropIn._();

  static void init({
    required void Function(Uint8List bytes, String name) onFile,
  }) {}

  static void dispose() {}
}