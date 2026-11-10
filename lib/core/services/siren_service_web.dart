// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import '../config/brand_config.dart';

class SirenServicePlatform {
  html.AudioElement? _audio;
  Timer? _titleBlinkTimer;
  String _origTitle = BrandConfig.appName;
  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  void startSiren({String? title, String? message}) {
    if (_isPlaying) return;
    _isPlaying = true;

    try {
      final cur = html.document.title;
      _origTitle = cur.isNotEmpty ? cur : BrandConfig.appName;
    } catch (_) {}

    // 1. Play authentic police siren audio
    try {
      _audio = html.AudioElement('/sounds/police_siren.wav')
        ..loop = true
        ..volume = 1.0;

      final playPromise = _audio?.play();
      if (playPromise != null) {
        playPromise.catchError((err) {
          debugPrint('[SIREN] Autoplay prevented, unlocking on next user interaction: $err');
          html.EventListener? unlock;
          unlock = (html.Event _) {
            if (_isPlaying && _audio != null) {
              _audio!.play().catchError((_) {});
            }
            if (unlock != null) {
              html.window.removeEventListener('click', unlock);
              html.window.removeEventListener('pointerdown', unlock);
            }
          };
          html.window.addEventListener('click', unlock);
          html.window.addEventListener('pointerdown', unlock);
        });
      }
    } catch (e) {
      debugPrint('[SIREN] Audio play error: $e');
    }

    // 2. Start title flashing & notify if outside active app
    _startTitleFlash(title ?? 'THEFT ALARM');
    _notifyIfHidden(title: title, message: message);
  }

  void _startTitleFlash(String heading) {
    _titleBlinkTimer?.cancel();
    bool toggle = false;
    _titleBlinkTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      if (!_isPlaying) return;
      try {
        html.document.title = toggle
            ? '🚨 🚨 $heading 🚨 🚨'
            : '⚠️ ⚠️ CHECK VEHICLE IMMEDIATELY ⚠️ ⚠️';
        toggle = !toggle;
      } catch (_) {}
    });
  }

  void _notifyIfHidden({String? title, String? message}) {
    try {
      final bool isHidden = html.document.hidden ?? false;
      if (isHidden) {
        if (html.Notification.permission == 'granted') {
          html.Notification(
            '🚨 ${title ?? "THEFT ALARM: Vehicle Moved!"}',
            body: message ?? 'Vehicle moved or engine turned ON while Safety Parking was active!',
            icon: '/favicon.png',
            tag: 'safety_park_theft',
          );
        } else if (html.Notification.permission != 'denied') {
          html.Notification.requestPermission().then((perm) {
            if (perm == 'granted') {
              html.Notification(
                '🚨 ${title ?? "THEFT ALARM: Vehicle Moved!"}',
                body: message ?? 'Vehicle moved or engine turned ON while Safety Parking was active!',
                icon: '/favicon.png',
                tag: 'safety_park_theft',
              );
            }
          });
        }
      }
    } catch (_) {}
  }

  void stopSiren() {
    _isPlaying = false;

    try {
      if (_audio != null) {
        _audio!.pause();
        _audio!.currentTime = 0;
        _audio = null;
      }
    } catch (_) {}

    _titleBlinkTimer?.cancel();
    _titleBlinkTimer = null;
    try {
      html.document.title = _origTitle;
    } catch (_) {}
  }
}

SirenServicePlatform createSirenService() => SirenServicePlatform();
