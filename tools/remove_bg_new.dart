import 'dart:io';
import 'package:image/image.dart';

void main() {
  final file = File('assets/images/vehicles/car.png');
  final img = decodeImage(file.readAsBytesSync());
  if (img == null) return;

  // Assume the top-left pixel is the background color
  final bgPixel = img.getPixel(0, 0);
  final bgR = bgPixel.r;
  final bgG = bgPixel.g;
  final bgB = bgPixel.b;

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

      // Check if it matches the background color (within a small tolerance)
      if ((r - bgR).abs() < 20 && (g - bgG).abs() < 20 && (b - bgB).abs() < 20) {
        img.setPixelRgba(x, y, 0, 0, 0, 0); // Make transparent
      } else {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }

  // Crop to bounding box with some padding
  minX = (minX - 10).clamp(0, img.width);
  minY = (minY - 10).clamp(0, img.height);
  maxX = (maxX + 10).clamp(0, img.width);
  maxY = (maxY + 10).clamp(0, img.height);

  final cropped = copyCrop(img, x: minX, y: minY, width: maxX - minX, height: maxY - minY);
  
  // Resize to a reasonable height
  final resized = copyResize(cropped, height: 120);

  file.writeAsBytesSync(encodePng(resized));
  
  // Also copy to the artifact directory so the preview updates!
  final artifactFile = File(r'C:\Users\mvach\.gemini\antigravity-ide\brain\6062737d-f911-4702-9e28-3776e27e423b\car.png');
  artifactFile.writeAsBytesSync(encodePng(resized));

  print('Removed background and saved car.png successfully.');
}
