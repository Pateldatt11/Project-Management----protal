import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Opens the browser's native print preview for a complete HTML document.
///
/// This implementation is compiled only for Flutter Web through the conditional
/// import in `report_html_printer.dart`.
///
/// A new same-origin window is opened synchronously before the first `await` so
/// Chrome, Edge, and Firefox treat it as a direct user action. The generated
/// HTML/CSS report is then written into that window and its native `print()`
/// method opens the standard browser print preview.
Future<bool> printHtml({
  required String title,
  required String html,
}) async {
  web.Window? printWindow;

  try {
    // This must happen before the first await; otherwise the browser may block
    // the window as an unsolicited popup.
    printWindow = web.window.open('', '_blank');

    if (printWindow == null) {
      return false;
    }

    final document = printWindow.document;

    document.open();
    document.write(html.toJS);
    document.close();

    // Set the browser-tab title after the new document has been created.
    document.title = title;

    // Allow CSS, inline SVG charts, fonts, and A4 page layout to settle.
    await Future<void>.delayed(const Duration(milliseconds: 700));

    if (printWindow.closed) {
      return false;
    }

    printWindow.print();
    return true;
  } catch (_) {
    try {
      printWindow?.close();
    } catch (_) {
      // Ignore cleanup failures.
    }
    return false;
  }
}
