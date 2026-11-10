import 'dart:io';
import 'package:image/image.dart';

void main() {
  final bytes = File('assets/images/vehicles/car_topdown.png').readAsBytesSync();
  final img = decodeImage(bytes);
  if (img != null) {
    print('car_topdown.png: width=${img.width}, height=${img.height}');
  }
}
