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

  // Flood fill background
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
    if (mask.getPixel(p.x, p.y).r == 255) continue; 

    final c = img.getPixel(p.x, p.y);
    if ((c.r - bgR).abs() < 30 && (c.g - bgG).abs() < 30 && (c.b - bgB).abs() < 30) {
      mask.setPixelRgba(p.x, p.y, 255, 0, 0, 0); 
      queue.add(Point(p.x + 1, p.y));
      queue.add(Point(p.x - 1, p.y));
      queue.add(Point(p.x, p.y + 1));
      queue.add(Point(p.x, p.y - 1));
    }
  }

  final outImg = Image(width: img.width, height: img.height, numChannels: 4);

  for (int y = 0; y < img.height; y++) {
    for (int x = 0; x < img.width; x++) {
      final p = img.getPixel(x, y);
      int a = mask.getPixel(x, y).r == 255 ? 0 : 255;
      
      // Also remove any green fringe (G much higher than R and B)
      if (p.g > p.r + 20 && p.g > p.b + 20) {
        a = 0;
      }
      
      // Smooth edges
      if (a == 255) {
         int bgNeighbors = 0;
         if (x>0 && mask.getPixel(x-1, y).r == 255) bgNeighbors++;
         if (x<img.width-1 && mask.getPixel(x+1, y).r == 255) bgNeighbors++;
         if (y>0 && mask.getPixel(x, y-1).r == 255) bgNeighbors++;
         if (y<img.height-1 && mask.getPixel(x, y+1).r == 255) bgNeighbors++;
         
         if (bgNeighbors > 2) {
           a = 0;
         } else if (bgNeighbors > 0) {
           a = 128; // Anti-alias edge
         }
      }
      
      outImg.setPixelRgba(x, y, p.r, p.g, p.b, a);
    }
  }

  // Save WITHOUT rotating, keeping it 60x120
  File('assets/images/vehicles/car.png').writeAsBytesSync(encodePng(outImg));
  print('Successfully processed white_car.png to car.png');
}

class Point {
  final int x;
  final int y;
  Point(this.x, this.y);
}
