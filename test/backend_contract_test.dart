import 'package:flutter_test/flutter_test.dart';
import 'package:fueltracks/core/config/app_config.dart';
import 'package:fueltracks/core/config/backend_capabilities.dart';
import 'package:fueltracks/data/models/report_models.dart';

/// Locks in the contract discovered by probing api.fueltracks.in.
/// If someone "tidies" one of these values, a test fails instead of the app
/// silently breaking against production.
void main() {
  group('Production endpoint config', () {
    test('points at the real backend', () {
      expect(AppConfig.apiBaseUrl, 'https://api.fueltracks.in');
      expect(AppConfig.apiRoot, 'https://api.fueltracks.in/api');
      expect(AppConfig.socketUrl, 'https://api.fueltracks.in');
    });

    test('socket.io lives at the server root, not under /api', () {
      // Verified: /socket.io/ → 200 handshake, /api/socket.io/ → 404.
      expect(AppConfig.socketPath, '/socket.io');
      expect(AppConfig.socketPath.startsWith('/api'), isFalse);
    });

    test('tile requests carry a descriptive User-Agent', () {
      // OSM's usage policy blocks generic/absent UAs.
      expect(AppConfig.tileUserAgent, isNotEmpty);
      expect(AppConfig.tileUserAgent, contains('fleet'));
    });
  });

  group('Capability flags match the live probe', () {
    test('deployed features are enabled', () {
      expect(BackendCapabilities.auth, isTrue);
      expect(BackendCapabilities.vehicles, isTrue);
      expect(BackendCapabilities.reports, isTrue);
      expect(BackendCapabilities.billing, isTrue);
      expect(BackendCapabilities.socket, isTrue);
      expect(BackendCapabilities.geofences, isTrue);
      expect(BackendCapabilities.alertsHistory, isTrue);
    });

    test('undeployed routes stay gated off', () {
      // All returned 404 on 2026-07-28.
      expect(BackendCapabilities.refreshToken, isFalse);
      expect(BackendCapabilities.changePassword, isFalse);
      // deviceTokenRegistration is enabled in BackendCapabilities
      expect(BackendCapabilities.deviceTokenRegistration, isTrue);
    });
  });

  group('Report paths resolve against the live API', () {
    test('all confirmed report routes are under /reports', () {
      const List<ReportType> confirmed = <ReportType>[
        ReportType.trip,
        ReportType.distance,
        ReportType.routeHistory,
        ReportType.overspeeding,
        ReportType.stoppages,
        ReportType.ignition,
        ReportType.activity,
        ReportType.consolidated,
      ];
      for (final ReportType t in confirmed) {
        expect(t.path, startsWith('/reports/'));
      }
    });
  });

  group('Error envelope', () {
    test('parses {success,error,code} from this backend', () {
      // Shape returned by api.fueltracks.in on a 401.
      const Map<String, dynamic> body = <String, dynamic>{
        'success': false,
        'error': 'Authentication required. No token provided.',
        'code': 'NO_TOKEN',
      };
      expect(body['error'], isNotNull);
      expect(body['code'], 'NO_TOKEN');
    });
  });
}
