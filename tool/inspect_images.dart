
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final files = [
    'assets/images/logo_emblem.png',
    'assets/images/app_icon.png',
    'assets/images/logo_icon.jpg',
    'assets/images/logo_icon_transparent.png',
  ];

  for (final path in files) {
    final file = File(path);
    if (!file.existsSync()) {
      print('$path: NOT FOUND');
      continue;
    }
    final bytes = file.readAsBytesSync();
    final image = img.decodeImage(bytes);
    if (image == null) {
      print('$path: FAILED TO DECODE');
    } else {
      print('$path: ${image.width}x${image.height}, numChannels=${image.numChannels}, hasAlpha=${image.hasAlpha}');
    }
  }
}
