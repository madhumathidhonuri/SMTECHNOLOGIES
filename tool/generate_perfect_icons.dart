import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

void main() {
  print('--- Generating Perfect FuelTracks App Icons ---');

  final srcFile = File('assets/images/logo_emblem.png');
  if (!srcFile.existsSync()) {
    print('Error: assets/images/logo_emblem.png not found');
    return;
  }

  final srcImage = img.decodeImage(srcFile.readAsBytesSync())!;
  print('Source image loaded: ${srcImage.width}x${srcImage.height}');

  // Circular emblem parameters
  const double cx = 511.5;
  const double cy = 510.5;
  const double radius = 453.0;
  const double feather = 2.0;

  // 1. Extract circular emblem with transparent alpha & anti-aliased edge
  final emblemSize = (radius * 2).toInt(); // ~906
  final emblem = img.Image(
    width: emblemSize,
    height: emblemSize,
    numChannels: 4,
  );

  for (int y = 0; y < emblemSize; y++) {
    for (int x = 0; x < emblemSize; x++) {
      final srcX = (cx - radius + x).round();
      final srcY = (cy - radius + y).round();

      final dx = x - radius;
      final dy = y - radius;
      final dist = math.sqrt(dx * dx + dy * dy);

      if (dist <= radius - feather) {
        if (srcX >= 0 && srcX < srcImage.width && srcY >= 0 && srcY < srcImage.height) {
          final p = srcImage.getPixel(srcX, srcY);
          emblem.setPixelRgba(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), 255);
        }
      } else if (dist < radius + feather) {
        final alpha = ((radius + feather - dist) / (feather * 2) * 255).clamp(0, 255).toInt();
        if (srcX >= 0 && srcX < srcImage.width && srcY >= 0 && srcY < srcImage.height) {
          final p = srcImage.getPixel(srcX, srcY);
          emblem.setPixelRgba(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), alpha);
        }
      } else {
        emblem.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }

  print('Emblem extracted with anti-aliased alpha: ${emblem.width}x${emblem.height}');

  // 2. Create Master App Icon (1024x1024) with deep luxury navy background (#0B1020)
  final masterIcon = img.Image(width: 1024, height: 1024, numChannels: 4);
  // Fill with brand background #0B1020
  for (int y = 0; y < 1024; y++) {
    for (int x = 0; x < 1024; x++) {
      // Subtle top-left to bottom-right radial/linear gradient
      final t = (x + y) / 2048.0;
      final r = (11 * (1 - t * 0.4)).toInt().clamp(6, 15);
      final g = (16 * (1 - t * 0.4)).toInt().clamp(10, 22);
      final b = (32 * (1 - t * 0.3)).toInt().clamp(20, 42);
      masterIcon.setPixelRgba(x, y, r, g, b, 255);
    }
  }

  // Scale emblem to ~740px for standard icon
  const int masterEmblemSize = 740;
  final scaledMasterEmblem = img.copyResize(
    emblem,
    width: masterEmblemSize,
    height: masterEmblemSize,
    interpolation: img.Interpolation.cubic,
  );

  // Composite scaled emblem onto masterIcon at center
  final masterOffset = (1024 - masterEmblemSize) ~/ 2;
  img.compositeImage(
    masterIcon,
    scaledMasterEmblem,
    dstX: masterOffset,
    dstY: masterOffset,
  );

  File('assets/images/app_icon_master.png').writeAsBytesSync(img.encodePng(masterIcon));
  File('assets/images/app_icon.png').writeAsBytesSync(img.encodePng(masterIcon));
  print('Saved assets/images/app_icon_master.png and app_icon.png');

  // 3. Create Adaptive Icon Foreground (1024x1024 transparent, emblem scaled to ~600px)
  // Safe zone for Android adaptive icon is central 66% (diameter ~600-640px)
  final adaptiveForeground = img.Image(width: 1024, height: 1024, numChannels: 4);
  // Transparent background
  for (int y = 0; y < 1024; y++) {
    for (int x = 0; x < 1024; x++) {
      adaptiveForeground.setPixelRgba(x, y, 0, 0, 0, 0);
    }
  }

  const int adaptiveEmblemSize = 610; // Exactly 60% of 1024 canvas
  final scaledAdaptiveEmblem = img.copyResize(
    emblem,
    width: adaptiveEmblemSize,
    height: adaptiveEmblemSize,
    interpolation: img.Interpolation.cubic,
  );

  final adaptiveOffset = (1024 - adaptiveEmblemSize) ~/ 2;
  img.compositeImage(
    adaptiveForeground,
    scaledAdaptiveEmblem,
    dstX: adaptiveOffset,
    dstY: adaptiveOffset,
  );

  File('assets/images/app_icon_foreground.png').writeAsBytesSync(img.encodePng(adaptiveForeground));
  print('Saved assets/images/app_icon_foreground.png (transparent 1024x1024)');

  // 4. Generate all Android density mipmaps and drawables
  final densities = <String, int>{
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };

  final adaptiveDensities = <String, int>{
    'mdpi': 108,
    'hdpi': 162,
    'xhdpi': 216,
    'xxhdpi': 324,
    'xxxhdpi': 432,
  };

  for (final entry in densities.entries) {
    final density = entry.key;
    final size = entry.value;

    final mipmapDir = Directory('android/app/src/main/res/mipmap-$density');
    if (!mipmapDir.existsSync()) {
      mipmapDir.createSync(recursive: true);
    }

    final resizedIcon = img.copyResize(
      masterIcon,
      width: size,
      height: size,
      interpolation: img.Interpolation.cubic,
    );

    // Save standard ic_launcher.png
    File('${mipmapDir.path}/ic_launcher.png').writeAsBytesSync(img.encodePng(resizedIcon));

    // Save circular ic_launcher_round.png
    final roundIcon = img.Image(width: size, height: size, numChannels: 4);
    final rRadius = size / 2.0;
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final dx = x - rRadius + 0.5;
        final dy = y - rRadius + 0.5;
        final dist = math.sqrt(dx * dx + dy * dy);
        final srcP = resizedIcon.getPixel(x, y);
        if (dist <= rRadius - 1.0) {
          roundIcon.setPixelRgba(x, y, srcP.r.toInt(), srcP.g.toInt(), srcP.b.toInt(), srcP.a.toInt());
        } else if (dist < rRadius + 0.5) {
          final alpha = ((rRadius + 0.5 - dist) / 1.5 * srcP.a).clamp(0, 255).toInt();
          roundIcon.setPixelRgba(x, y, srcP.r.toInt(), srcP.g.toInt(), srcP.b.toInt(), alpha);
        } else {
          roundIcon.setPixelRgba(x, y, 0, 0, 0, 0);
        }
      }
    }
    File('${mipmapDir.path}/ic_launcher_round.png').writeAsBytesSync(img.encodePng(roundIcon));
    print('Generated mipmap-$density: ic_launcher.png and ic_launcher_round.png ($size x $size)');
  }

  // Generate adaptive icon foregrounds
  for (final entry in adaptiveDensities.entries) {
    final density = entry.key;
    final size = entry.value;

    final drawableDir = Directory('android/app/src/main/res/drawable-$density');
    if (!drawableDir.existsSync()) {
      drawableDir.createSync(recursive: true);
    }

    final resizedForeground = img.copyResize(
      adaptiveForeground,
      width: size,
      height: size,
      interpolation: img.Interpolation.cubic,
    );

    File('${drawableDir.path}/ic_launcher_foreground.png').writeAsBytesSync(img.encodePng(resizedForeground));
    print('Generated drawable-$density: ic_launcher_foreground.png ($size x $size)');
  }

  print('--- All Android App Icons successfully generated! ---');
}
