Future<void> downloadFileUniversal({
  required String content,
  required String fileName,
  required String mimeType,
}) async {
  throw UnsupportedError('Universal download is not supported on this platform');
}

Future<void> openPrintablePdfUniversal({
  required String htmlContent,
  required String fileName,
}) async {
  throw UnsupportedError('Printable PDF is not supported on this platform');
}
