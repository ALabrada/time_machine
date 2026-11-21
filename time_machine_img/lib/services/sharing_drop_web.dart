import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web implementation of the "drop-in" import used by [SharingService].
///
/// The browser has no filesystem folder to watch (unlike desktop) and no share
/// intent (unlike mobile), so the drop-in target is the whole window: files
/// dragged onto the page from the OS — e.g. an archive produced by the export
/// flow — are imported exactly like files dropped into the desktop drop-in
/// folder. Every dropped file is delivered through [onFile] as raw bytes.
final class SharingDropIn {
  SharingDropIn._();

  static void Function(web.Event)? _dragOverHandler;
  static void Function(web.Event)? _dropHandler;

  static void init({
    required void Function(Uint8List bytes, String name) onFile,
  }) {
    if (_dragOverHandler != null) {
      return;
    }
    _dragOverHandler = (event) {
      event.preventDefault();
      final dataTransfer = (event as web.DragEvent).dataTransfer;
      if (dataTransfer != null) {
        dataTransfer.dropEffect = 'copy';
      }
    };
    _dropHandler = (event) {
      event.preventDefault();
      final files = (event as web.DragEvent).dataTransfer?.files;
      if (files == null || files.length == 0) {
        return;
      }
      for (var i = 0; i < files.length; i++) {
        final file = files.item(i);
        if (file != null) {
          _readFile(file, onFile);
        }
      }
    };
    web.window.addEventListener('dragover', _dragOverHandler!.toJS);
    web.window.addEventListener('drop', _dropHandler!.toJS);
  }

  static Future<void> _readFile(
    web.File file,
    void Function(Uint8List bytes, String name) onFile,
  ) async {
    final buffer = await file.arrayBuffer().toDart;
    onFile(Uint8List.view(buffer.toDart), file.name);
  }

  static void dispose() {
    final dragOver = _dragOverHandler;
    final drop = _dropHandler;
    if (dragOver == null || drop == null) {
      return;
    }
    web.window.removeEventListener('dragover', dragOver.toJS);
    web.window.removeEventListener('drop', drop.toJS);
    _dragOverHandler = null;
    _dropHandler = null;
  }
}