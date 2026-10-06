// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<bool> downloadTextFile({
  required String fileName,
  required String content,
  String mimeType = 'text/plain;charset=utf-8',
}) async {
  final blob = html.Blob(<Object>[content], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  try {
    final anchor = html.AnchorElement(href: url)
      ..download = fileName
      ..style.display = 'none';
    html.document.body?.children.add(anchor);
    anchor.click();
    anchor.remove();
    return true;
  } finally {
    html.Url.revokeObjectUrl(url);
  }
}
