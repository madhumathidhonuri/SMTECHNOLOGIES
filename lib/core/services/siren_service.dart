import 'siren_service_stub.dart'
    if (dart.library.html) 'siren_service_web.dart';

class SirenService {
  SirenService._();
  static final SirenService instance = SirenService._();

  final SirenServicePlatform _platform = createSirenService();

  bool get isPlaying => _platform.isPlaying;

  void start({String? title, String? message}) {
    _platform.startSiren(title: title, message: message);
  }

  void stop() {
    _platform.stopSiren();
  }
}
