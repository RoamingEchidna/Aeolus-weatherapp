import 'package:flutter_test/flutter_test.dart';
import 'package:weather_gov/models/weather_alert.dart';

void main() {
  group('WeatherAlert.fromJson', () {
    test('parses all fields from NWS alert feature', () {
      final json = {
        'properties': {
          'event': 'Flood Watch',
          'severity': 'Moderate',
          'headline': 'Flood Watch in effect until 8 PM PDT',
          'description': 'Heavy rainfall expected.',
          'instruction': 'Monitor local forecasts.',
          'onset': '2026-04-04T14:00:00-07:00',
          'expires': '2026-04-05T20:00:00-07:00',
        }
      };

      final alert = WeatherAlert.fromJson(json);

      expect(alert.event, 'Flood Watch');
      expect(alert.severity, 'Moderate');
      expect(alert.headline, 'Flood Watch in effect until 8 PM PDT');
      expect(alert.description, 'Heavy rainfall expected.');
      expect(alert.instruction, 'Monitor local forecasts.');
      expect(alert.onset, DateTime.parse('2026-04-04T14:00:00-07:00'));
      expect(alert.expires, DateTime.parse('2026-04-05T20:00:00-07:00'));
    });

    test('falls back to effective when onset is null', () {
      final json = {
        'properties': {
          'event': 'Wind Advisory',
          'severity': 'Minor',
          'headline': 'Wind Advisory',
          'description': 'Gusty winds.',
          'instruction': null,
          'onset': null,
          'effective': '2026-04-04T10:00:00-07:00',
          'expires': '2026-04-04T18:00:00-07:00',
        }
      };

      final alert = WeatherAlert.fromJson(json);
      expect(alert.onset, DateTime.parse('2026-04-04T10:00:00-07:00'));
      expect(alert.instruction, '');
    });
  });

  group('WeatherAlert.alertColor', () {
    test('Extreme returns red', () {
      expect(WeatherAlert.alertColor('Extreme').toARGB32(), 0xFFD32F2F);
    });
    test('Severe returns red', () {
      expect(WeatherAlert.alertColor('Severe').toARGB32(), 0xFFD32F2F);
    });
    test('Moderate returns orange', () {
      expect(WeatherAlert.alertColor('Moderate').toARGB32(), 0xFFF57C00);
    });
    test('Minor returns yellow', () {
      expect(WeatherAlert.alertColor('Minor').toARGB32(), 0xFFF9A825);
    });
    test('Unknown returns orange', () {
      expect(WeatherAlert.alertColor('Unknown').toARGB32(), 0xFFF57C00);
    });
  });

  group('WeatherAlert JSON round-trip', () {
    test('toJson -> fromStoredJson preserves values', () {
      final original = WeatherAlert(
        event: 'Flood Watch',
        severity: 'Moderate',
        headline: 'Flood Watch',
        description: 'Heavy rain.',
        instruction: 'Be prepared.',
        onset: DateTime.utc(2026, 4, 4, 14),
        expires: DateTime.utc(2026, 4, 5, 20),
      );

      final restored = WeatherAlert.fromStoredJson(original.toJson());
      expect(restored.event, original.event);
      expect(restored.severity, original.severity);
      expect(restored.onset, original.onset);
    });
  });
}
