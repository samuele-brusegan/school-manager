import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// URL http(s) nel testo libero di compiti ed eventi.
final urlPattern = RegExp(r'https?://\S+');

/// Testo con rilevamento dei link: in modalità compatta ogni URL è
/// sostituito dall'etichetta "LINK" tappabile, altrimenti il testo è
/// mostrato integralmente.
class LinkedText extends StatefulWidget {
  const LinkedText(this.text, {super.key, required this.compact});

  final String text;
  final bool compact;

  @override
  State<LinkedText> createState() => _LinkedTextState();
}

class _LinkedTextState extends State<LinkedText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    final matches = urlPattern.allMatches(widget.text).toList();
    if (!widget.compact || matches.isEmpty) {
      return Text(widget.text);
    }
    final linkStyle = TextStyle(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
      fontWeight: FontWeight.w600,
    );
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in matches) {
      var url = match.group(0)!;
      // Punteggiatura finale (".", ")", ecc.) quasi mai fa parte
      // dell'URL: resta testo normale.
      final trailing = RegExp(r'[.,;:!?)\]]+$').firstMatch(url);
      final suffix = trailing?.group(0) ?? '';
      url = url.substring(0, url.length - suffix.length);
      if (match.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, match.start)));
      }
      if (url.isNotEmpty) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => launchUrl(Uri.parse(url),
              mode: LaunchMode.externalApplication);
        _recognizers.add(recognizer);
        spans.add(TextSpan(
            text: 'LINK', style: linkStyle, recognizer: recognizer));
      }
      if (suffix.isNotEmpty) spans.add(TextSpan(text: suffix));
      cursor = match.end;
    }
    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }
    return Text.rich(TextSpan(children: spans));
  }
}
