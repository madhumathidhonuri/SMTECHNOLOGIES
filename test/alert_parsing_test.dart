import 'package:flutter_test/flutter_test.dart';
import 'package:fueltracks/data/models/alert.dart';

void main() {
  group('Alert parsing for WhatsApp events', () {
    test('parses fuel_refill_final alert correctly', () {
      final json = {
        'id': '101',
        'imei': '123456789012345',
        'alert_type': 'fuel_refill_final',
        'alert_text': 'Fuel Refill of 45.2 L detected',
        'latitude': 17.3850,
        'longitude': 78.4867,
        'device_time': '2026-10-29T10:00:00Z',
        'created_at': '2026-10-29T10:00:05Z',
      };

      final alert = FleetAlert.fromJson(json);
      expect(alert.type, 'fuel_refill_final');
      expect(alert.severity, AlertSeverity.info);
      expect(alert.title, 'Fuel Refill Confirmed');
      expect(alert.message, 'Fuel Refill of 45.2 L detected');
    });

    test('parses fuel_theft alert correctly', () {
      final json = {
        'id': '102',
        'imei': '123456789012345',
        'alert_type': 'fuel_theft',
        'alert_text': 'Fuel theft of 25.0 L detected',
        'latitude': 17.3850,
        'longitude': 78.4867,
        'device_time': '2026-10-29T10:05:00Z',
        'created_at': '2026-10-29T10:05:05Z',
      };

      final alert = FleetAlert.fromJson(json);
      expect(alert.type, 'fuel_theft');
      expect(alert.severity, AlertSeverity.critical);
      expect(alert.title, 'Vehicle Theft Alarm');
      expect(alert.message, 'Fuel theft of 25.0 L detected');
    });
  });
}
