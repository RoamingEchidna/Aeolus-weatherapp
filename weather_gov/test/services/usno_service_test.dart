import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:weather_gov/services/usno_service.dart';
import 'package:weather_gov/models/astro_day.dart';

const _kUsnoResponse = '''
{
  "type": "Feature",
  "properties": {
    "data": {
      "sundata": [
        {"phen": "Begin Civil Twilight", "time": "06:16"},
        {"phen": "Rise",                 "time": "06:43"},
        {"phen": "Upper Transit",        "time": "13:10"},
        {"phen": "Set",                  "time": "19:38"},
        {"phen": "End Civil Twilight",   "time": "20:05"}
      ],
      "moondata": [
        {"phen": "Rise", "time": "14:38"},
        {"phen": "Set",  "time": "02:25"}
      ]
    }
  }
}
''';

http.Client _mockClient(String body, {int status = 200}) =>
    MockClient((_) async => http.Response(body, status));

void main() {
  final windowStart = DateTime(2026, 4, 7, 0, 0);
  final windowEnd   = DateTime(2026, 4, 7, 23, 0);

  group('UsnoService.fetchAstroData', () {
    test('parses sun and moon events for a single day', () async {
      final service = UsnoService(client: _mockClient(_kUsnoResponse));
      final days = await service.fetchAstroData(
        lat: 38.9, lon: -77.0,
        windowStart: windowStart, windowEnd: windowEnd,
        tzOffsetHours: -4,
      );

      expect(days.length, 1);
      final day = days.first;
      expect(day.isSentinel, isFalse);
      expect(day.sunrise,   DateTime(2026, 4, 7, 6, 43));
      expect(day.solarNoon, DateTime(2026, 4, 7, 13, 10));
      expect(day.sunset,    DateTime(2026, 4, 7, 19, 38));
      expect(day.beginCivilTwilight, DateTime(2026, 4, 7, 6, 16));
      expect(day.endCivilTwilight,   DateTime(2026, 4, 7, 20, 5));
      expect(day.moonrise, DateTime(2026, 4, 7, 14, 38));
      expect(day.moonset,  DateTime(2026, 4, 7, 2, 25));
    });

    test('returns sentinel on HTTP error', () async {
      final service = UsnoService(client: _mockClient('', status: 500));
      final days = await service.fetchAstroData(
        lat: 38.9, lon: -77.0,
        windowStart: windowStart, windowEnd: windowEnd,
        tzOffsetHours: -4,
      );

      expect(days.length, 1);
      expect(days.first.isSentinel, isTrue);
    });

    test('returns sentinel on malformed JSON', () async {
      final service = UsnoService(client: _mockClient('not json'));
      final days = await service.fetchAstroData(
        lat: 38.9, lon: -77.0,
        windowStart: windowStart, windowEnd: windowEnd,
        tzOffsetHours: -4,
      );

      expect(days.first.isSentinel, isTrue);
    });

    test('spans two calendar days for a multi-day window', () async {
      final service = UsnoService(client: _mockClient(_kUsnoResponse));
      final days = await service.fetchAstroData(
        lat: 38.9, lon: -77.0,
        windowStart: DateTime(2026, 4, 7, 0, 0),
        windowEnd:   DateTime(2026, 4, 8, 23, 0),
        tzOffsetHours: -4,
      );

      expect(days.length, 2);
    });
  });
}
