import 'dart:io';
import 'package:image/image.dart';

void main() {
  final file = File(r'C:\Users\mvach\.gemini\antigravity-ide\brain\6062737d-f911-4702-9e28-3776e27e423b\perfect_topdown_suv_1786716217015.png');
  var img = decodeImage(file.readAsBytesSync());
  if (img == null) return;

  // The car is vertically in the center. DALL-E outputs 1024x1024.
  // Crop the sides to make it 512x1024 (1:2 aspect ratio)
  img = copyCrop(img, x: 256, y: 0, width: 512, height: 1024);

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
    if ((c.r - bgR).abs() < 40 && (c.g - bgG).abs() < 40 && (c.b - bgB).abs() < 40) {
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
           a = 128; 
         }
      }
      
      outImg.setPixelRgba(x, y, p.r, p.g, p.b, a);
    }
  }

  File('assets/images/vehicles/car.png').writeAsBytesSync(encodePng(outImg));
  print('Successfully processed perfect AI topdown car to car.png');
}

class Point {
  final int x;
  final int y;
  Point(this.x, this.y);
}
