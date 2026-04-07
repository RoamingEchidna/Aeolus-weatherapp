import 'package:flutter_test/flutter_test.dart';
import 'package:weather_gov/models/saved_location.dart';
import 'package:weather_gov/models/hourly_period.dart';
import 'package:weather_gov/models/weather_alert.dart';

void main() {
  final samplePeriod = HourlyPeriod(
    startTime: DateTime.utc(2026, 4, 4, 21),
    temperature: 58,
    precipChance: 10,
    relativeHumidity: 17,
    dewpointF: 12.99,
    windSpeedMph: 3.0,
    windDirection: 'S',
    shortForecast: 'Partly Cloudy',
    iconUrl: 'https://example.com/icon.png',
  );

  final sampleAlert = WeatherAlert(
    event: 'Flood Watch',
    severity: 'Moderate',
    headline: 'Flood Watch',
    description: 'Heavy rain.',
    instruction: '',
    onset: DateTime.utc(2026, 4, 4, 14),
    expires: DateTime.utc(2026, 4, 5, 20),
  );

  group('SavedLocation JSON round-trip', () {
    test('toJson -> fromJson preserves all fields', () {
      final location = SavedLocation(
        displayName: 'Bishop, CA',
        lat: 37.3636,
        lon: -118.394,
        lastAccessed: DateTime.utc(2026, 4, 4),
        cachedForecast: [samplePeriod],
        cachedAlerts: [sampleAlert],
        cacheTimestamp: DateTime.utc(2026, 4, 4, 12),
      );

      final restored = SavedLocation.fromJson(location.toJson());

      expect(restored.displayName, 'Bishop, CA');
      expect(restored.lat, 37.3636);
      expect(restored.lon, -118.394);
      expect(restored.cachedForecast.length, 1);
      expect(restored.cachedForecast.first.temperature, 58);
      expect(restored.cachedAlerts.length, 1);
      expect(restored.cachedAlerts.first.event, 'Flood Watch');
    });
  });
}
