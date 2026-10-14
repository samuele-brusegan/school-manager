import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

/// Pagina interna per visualizzare l'allegato di una circolare: i byte
/// restano in memoria, nulla viene salvato nei documenti/download.
class AttachmentViewerPage extends StatelessWidget {
  const AttachmentViewerPage({
    super.key,
    required this.fileName,
    required this.bytes,
  });
  final String fileName;
  final Uint8List bytes;

  static const _imageExtensions = ['.png', '.jpg', '.jpeg', '.gif', '.webp'];
  static const _textExtensions = ['.txt', '.csv', '.md', '.json'];

  static bool isPdf(String fileName) =>
      fileName.toLowerCase().endsWith('.pdf');

  /// Icona rappresentativa per un allegato non-PDF.
  static IconData iconFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (_imageExtensions.any(lower.endsWith)) return Icons.image_outlined;
    if (lower.endsWith('.zip')) return Icons.folder_zip_outlined;
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
      return Icons.description_outlined;
    }
    if (_textExtensions.any(lower.endsWith)) return Icons.article_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final lower = fileName.toLowerCase();
    final Widget body;
    if (isPdf(fileName)) {
      body = _PdfBytesViewer(bytes: bytes);
    } else if (_imageExtensions.any(lower.endsWith)) {
      body = InteractiveViewer(
        maxScale: 8,
        child: Center(child: Image.memory(bytes)),
      );
    } else if (_textExtensions.any(lower.endsWith)) {
      body = SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          utf8.decode(bytes, allowMalformed: true),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
      );
    } else {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(iconFor(fileName), size: 56),
              const SizedBox(height: 12),
              Text(fileName, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'Questo tipo di file non è visualizzabile in-app.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(fileName, overflow: TextOverflow.ellipsis)),
      body: body,
    );
  }
}

/// Viewer PDF a tutta larghezza con zoom: renderizza ogni pagina come
/// immagine jpeg a doppia risoluzione e le impila in una colonna
/// scorrevole/zoomabile (pinch, doppio-tap, rotellina/trackpad).
class _PdfBytesViewer extends StatefulWidget {
  const _PdfBytesViewer({required this.bytes});
  final Uint8List bytes;

  @override
  State<_PdfBytesViewer> createState() => _PdfBytesViewerState();
}

class _PdfBytesViewerState extends State<_PdfBytesViewer> {
  final _transform = TransformationController();
  Offset _doubleTapAt = Offset.zero;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  /// Zoom puntuale con la rotellina del mouse (e pinch su trackpad).
  void _onWheel(PointerScrollEvent event) {
    final factor = event.scrollDelta.dy < 0 ? 1.2 : 1 / 1.2;
    final current = _transform.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(1.0, 8.0);
    _transform.value = next <= 1.0
        ? Matrix4.identity()
        : _zoomMatrix(factor: next / current, at: event.localPosition) *
            _transform.value;
  }

  /// Matrice che scala di [factor] mantenendo fermo il punto [at].
  Matrix4 _zoomMatrix({required double factor, required Offset at}) =>
      Matrix4.identity()
        ..translateByDouble(at.dx, at.dy, 0, 1)
        ..scaleByDouble(factor, factor, factor, 1)
        ..translateByDouble(-at.dx, -at.dy, 0, 1);

  /// Doppio tap: alterna tra zoom 2.5× sul punto toccato e vista intera.
  void _onDoubleTap() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    _transform.value = zoomed
        ? Matrix4.identity()
        : _zoomMatrix(factor: 2.5, at: _doubleTapAt);
  }

  Future<List<Uint8List>> _renderAll() async {
    // Sul web pdfx trasferisce l'ArrayBuffer al worker pdf.js e lo
    // scollega ("detached ArrayBuffer"): servire sempre una copia.
    final doc =
        await PdfDocument.openData(Uint8List.fromList(widget.bytes));
    final pages = <Uint8List>[];
    try {
      for (var index = 1; index <= doc.pagesCount; index++) {
        final page = await doc.getPage(index);
        final image = await page.render(
          width: page.width * 2,
          height: page.height * 2,
          format: PdfPageImageFormat.jpeg,
          quality: 85,
          backgroundColor: '#FFFFFF',
        );
        await page.close();
        if (image != null) pages.add(image.bytes);
      }
    } finally {
      await doc.close();
    }
    return pages;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Uint8List>>(
        future: _renderAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Impossibile mostrare il PDF.\n${snapshot.error}',
                  textAlign: TextAlign.center),
            );
          }
          final pages = snapshot.data;
          if (pages == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (pages.isEmpty) {
            return const Center(child: Text('Il PDF non ha pagine.'));
          }
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: LayoutBuilder(builder: (context, constraints) {
              return Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) _onWheel(event);
                },
                child: GestureDetector(
                  onDoubleTapDown: (details) =>
                      _doubleTapAt = details.localPosition,
                  onDoubleTap: _onDoubleTap,
                  child: InteractiveViewer(
                    transformationController: _transform,
                    minScale: 1,
                    maxScale: 8,
                    panEnabled: true,
                    scaleEnabled: true,
                    trackpadScrollCausesScale: true,
                    constrained: false,
                    alignment: Alignment.topCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final page in pages)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Image.memory(page,
                                width: constraints.maxWidth,
                                fit: BoxFit.fitWidth),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          );
        },
      );
}
