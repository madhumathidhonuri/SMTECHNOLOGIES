import 'dart:io';
import 'package:image/image.dart';

void main() {
  final bytes = File('assets/images/vehicles/white_car.png').readAsBytesSync();
  final img = decodeImage(bytes);
  if (img != null) {
    print('white_car.png raw: width=${img.width}, height=${img.height}');
  }
}
