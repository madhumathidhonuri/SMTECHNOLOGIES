import 'dart:io';
import 'package:image/image.dart';

void main() {
  final file = File('assets/images/vehicles/car.png');
  final bytes = file.readAsBytesSync();
  var img = decodeImage(bytes);
  if (img == null) return;
  
  // Rotate by 270 degrees (-90 degrees) so it faces UP
  img = copyRotate(img, angle: 270);
  
  file.writeAsBytesSync(encodePng(img));
  print('Rotated car.png successfully.');
}
