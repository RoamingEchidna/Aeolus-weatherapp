import 'package:flutter_test/flutter_test.dart';
import 'package:weather_gov/models/hourly_period.dart';

void main() {
  group('parseWindSpeed', () {
    test('parses single value', () {
      expect(parseWindSpeed('3 mph'), 3.0);
    });

    test('averages a range', () {
      expect(parseWindSpeed('10 to 15 mph'), 12.5);
    });

    test('returns 0 for empty/unknown', () {
      expect(parseWindSpeed('Calm'), 0.0);
    });
  });

  group('celsiusToFahrenheit', () {
    test('converts 0C to 32F', () {
      expect(celsiusToFahrenheit(0), 32.0);
    });

    test('converts 100C to 212F', () {
      expect(celsiusToFahrenheit(100), 212.0);
    });
  });

  group('HourlyPeriod.fromJson', () {
    test('parses all fields from API response', () {
      final json = {
        'startTime': '2026-04-04T21:00:00-07:00',
        'temperature': 58,
        'probabilityOfPrecipitation': {'unitCode': 'wmoUnit:percent', 'value': 10},
        'relativeHumidity': {'unitCode': 'wmoUnit:percent', 'value': 17},
        'dewpoint': {'unitCode': 'wmoUnit:degC', 'value': -10.56},
        'windSpeed': '3 mph',
        'windDirection': 'S',
        'shortForecast': 'Partly Cloudy',
        'icon': 'https://api.weather.gov/icons/land/night/few?size=small',
      };

      final period = HourlyPeriod.fromJson(json);

      expect(period.temperature, 58);
      expect(period.precipChance, 10);
      expect(period.relativeHumidity, 17);
      expect(period.dewpointF, closeTo(celsiusToFahrenheit(-10.56), 0.01));
      expect(period.windSpeedMph, 3.0);
      expect(period.windDirection, 'S');
      expect(period.shortForecast, 'Partly Cloudy');
      expect(period.iconUrl, contains('api.weather.gov'));
    });

    test('handles null precipitation and humidity values', () {
      final json = {
        'startTime': '2026-04-04T21:00:00-07:00',
        'temperature': 50,
        'probabilityOfPrecipitation': {'unitCode': 'wmoUnit:percent', 'value': null},
        'relativeHumidity': {'unitCode': 'wmoUnit:percent', 'value': null},
        'dewpoint': {'unitCode': 'wmoUnit:degC', 'value': null},
        'windSpeed': 'Calm',
        'windDirection': 'N',
        'shortForecast': 'Clear',
        'icon': '',
      };

      final period = HourlyPeriod.fromJson(json);
      expect(period.precipChance, 0);
      expect(period.relativeHumidity, 0);
      expect(period.windSpeedMph, 0.0);
    });
  });

  group('HourlyPeriod JSON round-trip', () {
    test('toJson -> fromStoredJson preserves values', () {
      final original = HourlyPeriod(
        startTime: DateTime.parse('2026-04-04T21:00:00.000'),
        temperature: 58,
        precipChance: 10,
        relativeHumidity: 17,
        dewpointF: 12.99,
        windSpeedMph: 3.0,
        windDirection: 'S',
        shortForecast: 'Partly Cloudy',
        iconUrl: 'https://example.com/icon.png',
      );

      final restored = HourlyPeriod.fromStoredJson(original.toJson());
      expect(restored.temperature, original.temperature);
      expect(restored.precipChance, original.precipChance);
      expect(restored.windSpeedMph, original.windSpeedMph);
      expect(restored.startTime, original.startTime);
    });
  });
}
