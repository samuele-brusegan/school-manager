import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Estrae testo grezzo dai flussi di un PDF per la ricerca full-text.
///
/// Non è un parser PDF completo: decomprime gli stream `FlateDecode`
/// (zlib, disponibile in `dart:convert` anche sul web) e raccoglie le
/// stringhe letterali `(…)` ed esadecimali `<…>` usate dagli operatori
/// di testo (Tj, TJ, ', "). Basta a indicizzare il contenuto delle
/// circolari per la ricerca in-app.
String extractPdfText(Uint8List bytes) {
  final out = StringBuffer();
  for (final stream in _pdfStreams(bytes)) {
    final decoded = _decodeStream(stream);
    if (decoded == null) continue;
    final text = latin1.decode(decoded, allowInvalid: true);
    for (final literal in _literalStrings(text)) {
      out.write(literal);
      out.write(' ');
    }
    for (final hex in _hexStrings(text)) {
      out.write(hex);
      out.write(' ');
    }
  }
  return out.toString();
}

/// Restituisce i byte grezzi di ogni `stream … endstream` del file.
Iterable<Uint8List> _pdfStreams(Uint8List bytes) sync* {
  const marker = 'stream';
  const end = 'endstream';
  var index = 0;
  while (index < bytes.length) {
    final start = _indexOf(bytes, marker, index);
    if (start < 0) break;
    var content = start + marker.length;
    // La parola chiave stream va seguita da \r\n, \n o \r.
    if (content + 1 < bytes.length &&
        bytes[content] == 0x0D &&
        bytes[content + 1] == 0x0A) {
      content += 2;
    } else if (content < bytes.length &&
        (bytes[content] == 0x0A || bytes[content] == 0x0D)) {
      content += 1;
    }
    final finish = _indexOf(bytes, end, content);
    if (finish < 0) break;
    yield Uint8List.sublistView(bytes, content, finish);
    index = finish + end.length;
  }
}

int _indexOf(Uint8List bytes, String pattern, int from) {
  outer:
  for (var i = from; i <= bytes.length - pattern.length; i++) {
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern.codeUnitAt(j)) continue outer;
    }
    return i;
  }
  return -1;
}

/// Decodifica uno stream: se è compresso prova zlib, altrimenti lo
/// restituisce così com'è (molti PDF hanno flussi di testo in chiaro).
Uint8List? _decodeStream(Uint8List stream) {
  const decoder = ZLibDecoder();
  try {
    return Uint8List.fromList(decoder.decodeBytes(stream));
  } catch (_) {
    // Alcuni stream hanno byte spurii prima dell'header zlib (0x78):
    // riprova dai primi 4 byte in poi.
    for (var i = 1; i <= 4 && i < stream.length; i++) {
      try {
        return Uint8List.fromList(
            decoder.decodeBytes(stream.sublist(i)));
      } catch (_) {}
    }
  }
  return stream;
}

/// Stringhe letterali `(testo)` con escape `\…` gestiti.
Iterable<String> _literalStrings(String s) sync* {
  final pattern = RegExp(r'\((?:\\.|[^\\()])*\)');
  for (final match in pattern.allMatches(s)) {
    yield _unescapeLiteral(match.group(0)!);
  }
}

String _unescapeLiteral(String literal) {
  final inner = literal.substring(1, literal.length - 1);
  final out = StringBuffer();
  for (var i = 0; i < inner.length; i++) {
    final ch = inner[i];
    if (ch != '\\' || i + 1 >= inner.length) {
      out.write(ch);
      continue;
    }
    final next = inner[++i];
    switch (next) {
      case 'n':
        out.write('\n');
      case 'r':
        out.write('\r');
      case 't':
        out.write('\t');
      case 'b':
        out.write('\b');
      case 'f':
        out.write('\f');
      case '\\':
      case '(':
      case ')':
        out.write(next);
      default:
        // Escape ottale \ddd o continuazione di riga.
        final octal = RegExp(r'[0-7]{1,3}')
            .matchAsPrefix(inner, i);
        if (octal != null) {
          out.writeCharCode(
              int.parse(octal.group(0)!, radix: 8) & 0xFF);
          i += octal.group(0)!.length - 1;
        } else if (next != '\n' && next != '\r') {
          out.write(next);
        }
    }
  }
  return out.toString();
}

/// Stringhe esadecimali `<AB12>`: spesso usate dai font CID. Decodifica
/// come UTF-16BE se c'è la BOM, altrimenti latin1.
Iterable<String> _hexStrings(String s) sync* {
  final pattern = RegExp(r'<([0-9A-Fa-f\s]+)>');
  for (final match in pattern.allMatches(s)) {
    final hex = match.group(1)!.replaceAll(RegExp(r'\s+'), '');
    if (hex.length < 4 || hex.length.isOdd) continue;
    final data = Uint8List(hex.length ~/ 2);
    var ok = true;
    for (var i = 0; i < data.length; i++) {
      final byte = int.tryParse(hex.substring(i * 2, i * 2 + 2),
          radix: 16);
      if (byte == null) {
        ok = false;
        break;
      }
      data[i] = byte;
    }
    if (!ok) continue;
    if (data.length >= 2 && data[0] == 0xFE && data[1] == 0xFF) {
      yield _decodeUtf16Be(data.sublist(2));
    } else {
      yield latin1.decode(data, allowInvalid: true);
    }
  }
}

String _decodeUtf16Be(Uint8List data) {
  final out = StringBuffer();
  for (var i = 0; i + 1 < data.length; i += 2) {
    out.writeCharCode((data[i] << 8) | data[i + 1]);
  }
  return out.toString();
}
