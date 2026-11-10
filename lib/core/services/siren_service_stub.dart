import 'dart:async';
import 'package:flutter/services.dart';

class SirenServicePlatform {
  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;
  Timer? _vibrateTimer;

  void startSiren({String? title, String? message}) {
    if (_isPlaying) return;
    _isPlaying = true;
    HapticFeedback.heavyImpact();
    _vibrateTimer?.cancel();
    _vibrateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!_isPlaying) return;
      HapticFeedback.heavyImpact();
    });
  }

  void stopSiren() {
    _isPlaying = false;
    _vibrateTimer?.cancel();
    _vibrateTimer = null;
  }
}

SirenServicePlatform createSirenService() => SirenServicePlatform();

