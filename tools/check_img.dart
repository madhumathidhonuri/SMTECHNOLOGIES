import 'dart:io';
import 'package:image/image.dart';

void main() {
  final bytes = File('assets/images/vehicles/car.png').readAsBytesSync();
  final img = decodeImage(bytes);
  if (img != null) {
    print('car.png: width=${img.width}, height=${img.height}');
  }
}
