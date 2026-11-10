import 'dart:io';
import 'package:image/image.dart';

void main() {
  final bytes = File('assets/images/vehicles/car_topdown.png').readAsBytesSync();
  final img = decodeImage(bytes);
  if (img != null) {
    bool hasTransparent = false;
    for (int y = 0; y < img.height; y++) {
      for (int x = 0; x < img.width; x++) {
        if (img.getPixel(x, y).a < 255) {
          hasTransparent = true;
          break;
        }
      }
      if (hasTransparent) break;
    }
    print('hasTransparent: $hasTransparent');
  }
}
