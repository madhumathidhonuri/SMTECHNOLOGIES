// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:convert';
import 'dart:html' as html;

Future<void> downloadFileUniversal({
  required String content,
  required String fileName,
  required String mimeType,
}) async {
  final List<int> bytes = utf8.encode(content);
  // Prepend UTF-8 Byte Order Mark (\uFEFF) for Excel & CSV compatibility
  final List<int> finalBytes = mimeType.contains('csv') || mimeType.contains('excel')
      ? <int>[0xEF, 0xBB, 0xBF, ...bytes]
      : bytes;

  final html.Blob blob = html.Blob(<dynamic>[finalBytes], mimeType);
  final String url = html.Url.createObjectUrlFromBlob(blob);
  final html.AnchorElement anchor = html.document.createElement('a') as html.AnchorElement
    ..href = url
    ..style.display = 'none'
    ..download = fileName;

  html.document.body?.children.add(anchor);
  anchor.click();
  html.document.body?.children.remove(anchor);
  html.Url.revokeObjectUrl(url);
}

Future<void> openPrintablePdfUniversal({
  required String htmlContent,
  required String fileName,
}) async {
  // Inject automatic print script inside HTML so the tab prints on load
  final String printableHtml = htmlContent.replaceFirst(
    '</body>',
    '<script>window.onload = function() { setTimeout(function() { window.print(); }, 250); };</script></body>',
  );

  final List<int> bytes = utf8.encode(printableHtml);
  final html.Blob blob = html.Blob(<dynamic>[bytes], 'text/html;charset=utf-8');
  final String url = html.Url.createObjectUrlFromBlob(blob);

  // Opens the blob in a new tab which renders the report and auto-triggers print
  html.window.open(url, '_blank');
}
