import 'dart:io';
import 'package:image/image.dart';

void main() {
  final file = File(r'C:\Users\mvach\.gemini\antigravity-ide\brain\aec296be-cb97-48a6-9ead-ab4d6ac75d94\white_car_topdown_1786647591760.png');
  final img = decodeImage(file.readAsBytesSync());
  if (img == null) return;

  int minX = img.width;
  int minY = img.height;
  int maxX = 0;
  int maxY = 0;

  for (int y = 0; y < img.height; y++) {
    for (int x = 0; x < img.width; x++) {
      final p = img.getPixel(x, y);
      final r = p.r;
      final g = p.g;
      final b = p.b;

      // Pure green is 0, 255, 0. A threshold approach:
      if (g > 150 && g > r + 50 && g > b + 50) {
        img.setPixelRgba(x, y, 0, 0, 0, 0); // Make transparent
      } else {
        // Find bounding box
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }

  // Add a small padding (20px)
  minX = (minX - 20).clamp(0, img.width);
  minY = (minY - 20).clamp(0, img.height);
  maxX = (maxX + 20).clamp(0, img.width);
  maxY = (maxY + 20).clamp(0, img.height);

  final cropped = copyCrop(img, x: minX, y: minY, width: maxX - minX, height: maxY - minY);

  // Resize so it's not too huge for a map marker
  final resized = copyResize(cropped, height: 120);

  final outFile = File('assets/images/vehicles/white_car.png');
  outFile.writeAsBytesSync(encodePng(resized));
  print('Saved white_car.png successfully.');
}
