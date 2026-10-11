import 'dart:js_interop';

import 'package:web/web.dart';

/// Scarica un file di testo nel browser creando un Blob e simulando il
/// click su un link di download.
void downloadTextFile(String fileName, String content) {
  final blob = Blob([content.toJS].toJS);
  final url = URL.createObjectURL(blob);
  HTMLAnchorElement()
    ..href = url
    ..target = 'blank'
    ..download = fileName
    ..click();
  URL.revokeObjectURL(url);
}
