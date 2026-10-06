import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

class PdfPreviewScreen extends StatelessWidget {
  const PdfPreviewScreen({
    super.key,
    required this.title,
    required this.pdfBytes,
  });

  final String title;
  final Uint8List pdfBytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Share / download PDF',
            onPressed: () => Printing.sharePdf(bytes: pdfBytes, filename: _safeFileName(title)),
            icon: const Icon(Icons.download_rounded),
          ),
        ],
      ),
      body: PdfPreview(
        build: (_) async => pdfBytes,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        pdfFileName: _safeFileName(title),
      ),
    );
  }

  static String _safeFileName(String title) {
    final clean = title.trim().isEmpty ? 'company_report' : title.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_\-]+'), '_');
    return '$clean.pdf';
  }
}
