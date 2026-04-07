import 'package:flutter_test/flutter_test.dart';
import 'package:weather_gov/models/hourly_period.dart';

void main() {
  group('HourlyPeriod.parseWindSpeed', () {
    test('parses single speed', () {
      expect(HourlyPeriod.parseWindSpeed('3 mph'), 3.0);
    });

    test('parses range as average', () {
      expect(HourlyPeriod.parseWindSpeed('10 to 15 mph'), 12.5);
    });

    test('returns 0 for empty string', () {
      expect(HourlyPeriod.parseWindSpeed(''), 0.0);
    });
  });

  group('HourlyPeriod.celsiusToFahrenheit', () {
    test('converts 0C to 32F', () {
      expect(HourlyPeriod.celsiusToFahrenheit(0), 32.0);
    });

    test('converts 100C to 212F', () {
      expect(HourlyPeriod.celsiusToFahrenheit(100), 212.0);
    });

    test('converts -10.56C correctly', () {
      expect(HourlyPeriod.celsiusToFahrenheit(-10.56), closeTo(12.99, 0.01));
    });
  });

  group('HourlyPeriod.windChillF', () {
    test('returns temperature when T > 50F', () {
      final p = _make(temp: 60, wind: 20);
      expect(p.windChillF, 60.0);
    });

    test('returns temperature when wind <= 3 mph', () {
      final p = _make(temp: 30, wind: 2);
      expect(p.windChillF, 30.0);
    });

    test('computes wind chill when cold and windy', () {
      final p = _make(temp: 30, wind: 20);
      // NWS formula result ~17°F
      expect(p.windChillF, closeTo(17.4, 0.5));
    });
  });

  group('HourlyPeriod.skyCoverPct', () {
    test('returns 15 for few-clouds icon', () {
      final p = _makeIcon('https://api.weather.gov/icons/land/night/few?size=small');
      expect(p.skyCoverPct, 15);
    });

    test('returns 5 for clear icon', () {
      final p = _makeIcon('https://api.weather.gov/icons/land/day/skc?size=small');
      expect(p.skyCoverPct, 5);
    });

    test('returns 70 for broken icon', () {
      final p = _makeIcon('https://api.weather.gov/icons/land/day/bkn?size=small');
      expect(p.skyCoverPct, 70);
    });

    test('returns 95 for overcast icon', () {
      final p = _makeIcon('https://api.weather.gov/icons/land/day/ovc?size=small');
      expect(p.skyCoverPct, 95);
    });

    test('falls back to shortForecast when icon has no sky code', () {
      final p = HourlyPeriod(
        startTime: DateTime.utc(2026, 4, 4, 21),
        temperature: 58,
        precipChance: 10,
        relativeHumidity: 17,
        dewpointF: 12.99,
        windSpeedMph: 3.0,
        windDirection: 'S',
        shortForecast: 'Mostly Cloudy',
        iconUrl: '',
      );
      expect(p.skyCoverPct, 70);
    });
  });

  group('HourlyPeriod.fromJson', () {
    test('parses all fields correctly', () {
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
      expect(period.dewpointF, closeTo(12.99, 0.01));
      expect(period.windSpeedMph, 3.0);
      expect(period.windDirection, 'S');
      expect(period.shortForecast, 'Partly Cloudy');
    });

    test('JSON round-trip via toJson/fromStoredJson', () {
      final original = HourlyPeriod(
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

      final restored = HourlyPeriod.fromStoredJson(original.toJson());

      expect(restored.temperature, 58);
      expect(restored.precipChance, 10);
      expect(restored.windSpeedMph, 3.0);
      expect(restored.iconUrl, 'https://example.com/icon.png');
    });
  });
}

HourlyPeriod _make({required int temp, required double wind}) => HourlyPeriod(
      startTime: DateTime.utc(2026, 4, 4),
      temperature: temp,
      precipChance: 0,
      relativeHumidity: 50,
      dewpointF: 32.0,
      windSpeedMph: wind,
      windDirection: 'N',
      shortForecast: 'Clear',
      iconUrl: 'https://api.weather.gov/icons/land/day/skc?size=small',
    );

HourlyPeriod _makeIcon(String iconUrl) => HourlyPeriod(
      startTime: DateTime.utc(2026, 4, 4),
      temperature: 58,
      precipChance: 0,
      relativeHumidity: 50,
      dewpointF: 32.0,
      windSpeedMph: 5.0,
      windDirection: 'N',
      shortForecast: '',
      iconUrl: iconUrl,
    );
