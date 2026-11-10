import 'dart:io';
import 'package:image/image.dart';

void main() {
  final file = File('assets/images/vehicles/white_car.png');
  final img = decodeImage(file.readAsBytesSync());
  if (img == null) return;

  final bgPixel = img.getPixel(0, 0);
  final bgR = bgPixel.r;
  final bgG = bgPixel.g;
  final bgB = bgPixel.b;

  final mask = Image(width: img.width, height: img.height, numChannels: 1);
  // 0 = background, 255 = foreground

  // Flood fill from edges
  final queue = <Point>[];
  for (int x = 0; x < img.width; x++) {
    queue.add(Point(x, 0));
    queue.add(Point(x, img.height - 1));
  }
  for (int y = 0; y < img.height; y++) {
    queue.add(Point(0, y));
    queue.add(Point(img.width - 1, y));
  }

  while (queue.isNotEmpty) {
    final p = queue.removeLast();
    if (p.x < 0 || p.x >= img.width || p.y < 0 || p.y >= img.height) continue;
    if (mask.getPixel(p.x, p.y).r == 255) continue; // Already visited

    final c = img.getPixel(p.x, p.y);
    if ((c.r - bgR).abs() < 25 && (c.g - bgG).abs() < 25 && (c.b - bgB).abs() < 25) {
      mask.setPixelRgba(p.x, p.y, 255, 0, 0, 0); // Mark as background
      queue.add(Point(p.x + 1, p.y));
      queue.add(Point(p.x - 1, p.y));
      queue.add(Point(p.x, p.y + 1));
      queue.add(Point(p.x, p.y - 1));
    }
  }

  final outImg = Image(width: img.width, height: img.height, numChannels: 4);

  // Apply mask with 1-pixel dilation for smoothing
  for (int y = 0; y < img.height; y++) {
    for (int x = 0; x < img.width; x++) {
      final p = img.getPixel(x, y);
      int a = mask.getPixel(x, y).r == 255 ? 0 : 255;
      
      // Smooth edges
      if (a == 255) {
         int bgNeighbors = 0;
         if (x>0 && mask.getPixel(x-1, y).r == 255) bgNeighbors++;
         if (x<img.width-1 && mask.getPixel(x+1, y).r == 255) bgNeighbors++;
         if (y>0 && mask.getPixel(x, y-1).r == 255) bgNeighbors++;
         if (y<img.height-1 && mask.getPixel(x, y+1).r == 255) bgNeighbors++;
         if (bgNeighbors > 0) a = 128; // Anti-alias edge
      }
      
      outImg.setPixelRgba(x, y, p.r, p.g, p.b, a);
    }
  }

  // NO ROTATION!! The original is already 60x120 (facing North)!
  File('assets/images/vehicles/car.png').writeAsBytesSync(encodePng(outImg));
  print('Flood-filled and smoothed perfectly without rotation.');
}

class Point {
  final int x;
  final int y;
  Point(this.x, this.y);
}
