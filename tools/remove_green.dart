import 'dart:io';
import 'package:image/image.dart';

void main() {
  final file = File('assets/images/vehicles/car.png');
  final img = decodeImage(file.readAsBytesSync());
  if (img == null) return;

  for (int y = 0; y < img.height; y++) {
    for (int x = 0; x < img.width; x++) {
      final p = img.getPixel(x, y);
      
      // If it's a green fringe pixel, make it transparent
      // A pixel is green if its G channel is significantly higher than R and B.
      // But we must be careful not to delete white pixels (where R, G, B are all high).
      if (p.g > p.r + 20 && p.g > p.b + 20) {
        img.setPixelRgba(x, y, 0, 0, 0, 0); // Make completely transparent
      } else if (p.a > 0) {
        // If it's not green, but it has low alpha, it might be a smoothed edge of a green pixel.
        // Let's just make sure there is absolutely no green tint.
        if (p.g > p.r + 10 && p.g > p.b + 10) {
           img.setPixelRgba(x, y, 0, 0, 0, 0);
        }
      }
    }
  }

  file.writeAsBytesSync(encodePng(img));
  print('Green fringe removed perfectly.');
}
