import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:weather_gov/models/astro_day.dart';
import 'package:weather_gov/models/hourly_period.dart';
import 'package:weather_gov/models/saved_location.dart';
import 'package:weather_gov/services/location_refresher.dart';
import 'package:weather_gov/services/nws_service.dart';
import 'package:weather_gov/services/openuv_service.dart';
import 'package:weather_gov/services/usno_service.dart';

// The merge rules compare against the real clock, so the fake forecast
// starts at the current hour instead of a fixed date.
final _forecastStart = DateTime.now().toUtc().copyWith(
    minute: 0, second: 0, millisecond: 0, microsecond: 0);

http.Client _nwsClient() => MockClient((request) async {
      if (request.url.path.contains('/points/')) {
        return http.Response('''
          {"properties":{"gridId":"VEF","gridX":16,"gridY":169,
           "forecastHourly":"https://api.weather.gov/gridpoints/VEF/16,169/forecast/hourly",
           "forecastGridData":"https://api.weather.gov/gridpoints/VEF/16,169",
           "relativeLocation":{"properties":{"city":"Bishop","state":"CA"}},
           "timeZone":"America/Los_Angeles"}}
        ''', 200);
      }
      if (request.url.path.contains('/forecast/hourly')) {
        return http.Response('''
          {"properties":{"periods":[
            {"startTime":"${_forecastStart.toIso8601String()}","temperature":58,
             "probabilityOfPrecipitation":{"unitCode":"wmoUnit:percent","value":0},
             "relativeHumidity":{"unitCode":"wmoUnit:percent","value":17},
             "dewpoint":{"unitCode":"wmoUnit:degC","value":-10.56},
             "windSpeed":"3 mph","windDirection":"S",
             "shortForecast":"Partly Cloudy",
             "icon":"https://api.weather.gov/icons/land/night/few?size=small"}
          ]}}
        ''', 200);
      }
      return http.Response('{"features":[]}', 200);
    });

http.Client _usnoClient() => MockClient((_) async => http.Response('''
      {"properties":{"data":{"sundata":[{"phen":"Rise","time":"06:43"}],
                             "moondata":[]}}}
    ''', 200));

// Every UV request fails, so any UV in the result came from the cache.
http.Client _failingUvClient() =>
    MockClient((_) async => http.Response('', 500));

LocationRefresher _makeRefresher() => LocationRefresher(
      nwsService: NwsService(client: _nwsClient()),
      usnoService: UsnoService(client: _usnoClient()),
      openUvService: OpenUvService(client: _failingUvClient()),
    );

HourlyPeriod _period(DateTime start) => HourlyPeriod(
      startTime: start,
      temperature: 50,
      precipChance: 0,
      relativeHumidity: 20,
      dewpointF: 20,
      windSpeedMph: 3,
      windDirection: 'S',
      shortForecast: 'Clear',
      iconUrl: '',
    );

SavedLocation _cached({
  List<HourlyPeriod> forecast = const [],
  List<AstroDay> astro = const [],
}) =>
    SavedLocation(
      displayName: 'Bishop, CA',
      lat: 37.36,
      lon: -118.39,
      lastAccessed: DateTime(2026, 1, 1),
      cachedForecast: forecast,
      cachedAlerts: const [],
      cacheTimestamp: DateTime(2026, 1, 1),
      cachedAstroData: astro,
      isPinned: true,
      postcode: '93514',
    );

void main() {
  group('LocationRefresher.refresh', () {
    test('keeps cached periods from the last 24 hours ahead of the new forecast',
        () async {
      final recent = _period(_forecastStart.subtract(const Duration(hours: 3)));
      final stale = _period(_forecastStart.subtract(const Duration(hours: 30)));

      final result = await _makeRefresher().refresh(
        displayName: 'Bishop, CA',
        lat: 37.36,
        lon: -118.39,
        cached: _cached(forecast: [stale, recent]),
      );

      expect(result.cachedForecast.map((p) => p.startTime),
          [recent.startTime, _forecastStart]);
    });

    test('keeps pin and postcode from the cached copy', () async {
      final result = await _makeRefresher().refresh(
        displayName: 'Bishop, CA',
        lat: 37.36,
        lon: -118.39,
        cached: _cached(),
      );

      expect(result.isPinned, isTrue);
      expect(result.postcode, '93514');
    });

    test('lastAccessed defaults to now but can be kept', () async {
      final before = DateTime.now();
      final bumped = await _makeRefresher().refresh(
        displayName: 'Bishop, CA', lat: 37.36, lon: -118.39,
        cached: _cached(),
      );
      final kept = await _makeRefresher().refresh(
        displayName: 'Bishop, CA', lat: 37.36, lon: -118.39,
        cached: _cached(),
        lastAccessed: DateTime(2026, 1, 1),
      );

      expect(bumped.lastAccessed.isBefore(before), isFalse);
      expect(kept.lastAccessed, DateTime(2026, 1, 1));
    });

    test('reuses cached UV when the UV fetch fails', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final result = await _makeRefresher().refresh(
        displayName: 'Bishop, CA',
        lat: 37.36,
        lon: -118.39,
        cached: _cached(astro: [AstroDay(date: today, uvIndex: 7)]),
      );

      final todayAstro = result.cachedAstroData.firstWhere((d) =>
          d.date.year == today.year &&
          d.date.month == today.month &&
          d.date.day == today.day);
      expect(todayAstro.uvIndex, 7);
    });

    test('a brand-new location starts unpinned with only the new forecast',
        () async {
      final result = await _makeRefresher().refresh(
        displayName: 'Bishop, CA',
        lat: 37.36,
        lon: -118.39,
      );

      expect(result.isPinned, isFalse);
      expect(result.cachedForecast.length, 1);
    });
  });
}
