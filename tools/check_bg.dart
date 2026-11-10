import 'dart:io';
import 'package:image/image.dart';

void main() {
  final bytes = File('assets/images/vehicles/car.png').readAsBytesSync();
  final img = decodeImage(bytes);
  if (img != null) {
    final p1 = img.getPixel(0, 0);
    print('top-left: r=${p1.r}, g=${p1.g}, b=${p1.b}, a=${p1.a}');
  }
}
