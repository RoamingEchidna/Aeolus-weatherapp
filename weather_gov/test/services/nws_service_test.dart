import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:weather_gov/services/nws_service.dart';

const _pointsResponse = '''
{
  "properties": {
    "gridId": "VEF",
    "gridX": 16,
    "gridY": 169,
    "forecastHourly": "https://api.weather.gov/gridpoints/VEF/16,169/forecast/hourly",
    "relativeLocation": {
      "properties": { "city": "Bishop", "state": "CA" }
    },
    "timeZone": "America/Los_Angeles"
  }
}
''';

const _hourlyResponse = '''
{
  "properties": {
    "periods": [
      {
        "startTime": "2026-04-04T21:00:00-07:00",
        "temperature": 58,
        "probabilityOfPrecipitation": {"unitCode": "wmoUnit:percent", "value": 0},
        "relativeHumidity": {"unitCode": "wmoUnit:percent", "value": 17},
        "dewpoint": {"unitCode": "wmoUnit:degC", "value": -10.56},
        "windSpeed": "3 mph",
        "windDirection": "S",
        "shortForecast": "Partly Cloudy",
        "icon": "https://api.weather.gov/icons/land/night/few?size=small"
      }
    ]
  }
}
''';

const _alertsResponse = '''
{
  "features": [
    {
      "properties": {
        "event": "Wind Advisory",
        "severity": "Minor",
        "headline": "Wind Advisory until 6 PM",
        "description": "Gusty winds.",
        "instruction": "Secure outdoor items.",
        "onset": "2026-04-04T09:00:00-07:00",
        "expires": "2026-04-04T18:00:00-07:00"
      }
    }
  ]
}
''';

void main() {
  group('NwsService.fetchForecast', () {
    test('returns location name, forecast periods, and alerts', () async {
      int callCount = 0;
      final client = MockClient((request) async {
        callCount++;
        if (request.url.path.contains('/points/')) {
          return http.Response(_pointsResponse, 200);
        }
        if (request.url.path.contains('/forecast/hourly')) {
          return http.Response(_hourlyResponse, 200);
        }
        if (request.url.path.contains('/alerts/active')) {
          return http.Response(_alertsResponse, 200);
        }
        return http.Response('not found', 404);
      });

      final service = NwsService(client: client);
      final result = await service.fetchForecast(37.3636, -118.394);

      expect(callCount, 3);
      expect(result.locationName, 'Bishop, CA');
      expect(result.periods.length, 1);
      expect(result.periods.first.temperature, 58);
      expect(result.alerts.length, 1);
      expect(result.alerts.first.event, 'Wind Advisory');
    });

    test('throws NwsUnsupportedLocationException on points 404', () async {
      final client = MockClient((_) async => http.Response('{}', 404));
      final service = NwsService(client: client);
      expect(
        () => service.fetchForecast(0.0, 0.0),
        throwsA(isA<NwsUnsupportedLocationException>()),
      );
    });
  });
}
