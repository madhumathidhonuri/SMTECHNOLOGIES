import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> downloadFileUniversal({
  required String content,
  required String fileName,
  required String mimeType,
}) async {
  final Directory dir = await getTemporaryDirectory();
  final File file = File('${dir.path}/$fileName');
  await file.writeAsString(content);

  await Share.shareXFiles(
    <XFile>[XFile(file.path)],
    subject: fileName,
    text: 'Exported report: $fileName',
  );
}

Future<void> openPrintablePdfUniversal({
  required String htmlContent,
  required String fileName,
}) async {
  final Directory dir = await getTemporaryDirectory();
  final String htmlFileName = fileName.replaceAll('.pdf', '.html');
  final File file = File('${dir.path}/$htmlFileName');
  await file.writeAsString(htmlContent);

  await Share.shareXFiles(
    <XFile>[XFile(file.path)],
    subject: fileName,
    text: 'Exported report document: $fileName',
  );
}
