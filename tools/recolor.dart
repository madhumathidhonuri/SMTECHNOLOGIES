import 'dart:io';
import 'package:image/image.dart';

void main() {
  final file = File('assets/models/colormap.png');
  final img = decodePng(file.readAsBytesSync())!;
  
  for (int y = 0; y < img.height; y++) {
    for (int x = 0; x < img.width; x++) {
      final pixel = img.getPixel(x, y);
      if (pixel.r > 150 && pixel.g < 100 && pixel.b < 100) {
        img.setPixelRgba(x, y, 255, 255, 255, pixel.a);
      }
    }
  }
  
  file.writeAsBytesSync(encodePng(img));
  print('Colormap updated!');
}
