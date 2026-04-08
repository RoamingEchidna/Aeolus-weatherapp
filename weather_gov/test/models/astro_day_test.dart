import 'package:flutter_test/flutter_test.dart';
import 'package:weather_gov/models/astro_day.dart';

void main() {
  final date = DateTime(2026, 4, 7);

  group('AstroDay.isSentinel', () {
    test('sentinel has all nulls', () {
      final s = AstroDay.sentinel(date);
      expect(s.isSentinel, isTrue);
      expect(s.sunrise, isNull);
      expect(s.sunset, isNull);
      expect(s.moonrise, isNull);
      expect(s.moonset, isNull);
    });

    test('non-sentinel is not sentinel', () {
      final a = AstroDay(
        date: date,
        beginCivilTwilight: DateTime(2026, 4, 7, 6, 16),
        sunrise: DateTime(2026, 4, 7, 6, 43),
        solarNoon: DateTime(2026, 4, 7, 13, 10),
        sunset: DateTime(2026, 4, 7, 19, 38),
        endCivilTwilight: DateTime(2026, 4, 7, 20, 5),
        moonrise: DateTime(2026, 4, 7, 14, 38),
        moonset: null,
      );
      expect(a.isSentinel, isFalse);
    });
  });

  group('AstroDay JSON round-trip', () {
    test('serializes and restores all fields', () {
      final original = AstroDay(
        date: date,
        beginCivilTwilight: DateTime(2026, 4, 7, 6, 16),
        sunrise: DateTime(2026, 4, 7, 6, 43),
        solarNoon: DateTime(2026, 4, 7, 13, 10),
        sunset: DateTime(2026, 4, 7, 19, 38),
        endCivilTwilight: DateTime(2026, 4, 7, 20, 5),
        moonrise: DateTime(2026, 4, 7, 14, 38),
        moonset: null,
      );

      final restored = AstroDay.fromStoredJson(original.toJson());

      expect(restored.date, original.date);
      expect(restored.sunrise, original.sunrise);
      expect(restored.sunset, original.sunset);
      expect(restored.solarNoon, original.solarNoon);
      expect(restored.moonrise, original.moonrise);
      expect(restored.moonset, isNull);
    });

    test('sentinel survives round-trip', () {
      final s = AstroDay.sentinel(date);
      final restored = AstroDay.fromStoredJson(s.toJson());
      expect(restored.isSentinel, isTrue);
    });
  });
}
