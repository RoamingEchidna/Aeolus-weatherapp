import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weather_gov/providers/forecast_provider.dart';
import 'package:weather_gov/services/nws_service.dart';
import 'package:weather_gov/services/cache_service.dart';
import 'package:weather_gov/services/usno_service.dart';
import 'package:weather_gov/services/openuv_service.dart';
import 'package:weather_gov/models/astro_day.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Client _makeNwsClient() {
  return MockClient((request) async {
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
          {"startTime":"2026-04-04T21:00:00-07:00","temperature":58,
           "probabilityOfPrecipitation":{"unitCode":"wmoUnit:percent","value":0},
           "relativeHumidity":{"unitCode":"wmoUnit:percent","value":17},
           "dewpoint":{"unitCode":"wmoUnit:degC","value":-10.56},
           "windSpeed":"3 mph","windDirection":"S",
           "shortForecast":"Partly Cloudy",
           "icon":"https://api.weather.gov/icons/land/night/few?size=small"}
        ]}}
      ''', 200);
    }
    return http.Response('{"features":[]}', 200); // alerts
  });
}

http.Client _makeNominatimClient() {
  return MockClient((_) async => http.Response('''
    [{"display_name":"Bishop, Inyo County, California, United States",
      "lat":"37.3636","lon":"-118.394"}]
  ''', 200));
}

http.Client _makeUsnoClient() {
  return MockClient((_) async => http.Response('''
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
            {"phen": "Rise", "time": "14:38"}
          ]
        }
      }
    }
  ''', 200));
}

// UV is optional data; a failed fetch is treated as "no UV".
OpenUvService _makeOpenUvService() =>
    OpenUvService(client: MockClient((_) async => http.Response('', 500)));

Future<ForecastProvider> _makeProvider({http.Client? usnoClient}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ForecastProvider(
    nwsService: NwsService(client: _makeNwsClient()),
    nominatimService: NominatimService(client: _makeNominatimClient()),
    cacheService: CacheService(prefs),
    usnoService: UsnoService(client: usnoClient ?? _makeUsnoClient()),
    openUvService: _makeOpenUvService(),
    prefs: prefs,
  );
}

void main() {
  group('ForecastProvider initial state', () {
    test('starts with no location', () async {
      final provider = await _makeProvider();
      expect(provider.currentLocation, isNull);
      expect(provider.isLoading, isFalse);
    });
  });

  group('ForecastProvider.searchLocation', () {
    test('sets currentLocation and saves to cache', () async {
      final provider = await _makeProvider();
      await provider.searchLocation('Bishop, CA');

      expect(provider.currentLocation, isNotNull);
      expect(provider.currentLocation!.displayName, contains('Bishop'));
      expect(provider.currentLocation!.cachedForecast.length, 1);
      expect(provider.savedLocations.length, 1);
      expect(provider.isLoading, isFalse);
    });

    test('sets errorMessage on location not found', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = ForecastProvider(
        nwsService: NwsService(client: _makeNwsClient()),
        nominatimService: NominatimService(
          client: MockClient((_) async => http.Response('[]', 200)),
        ),
        cacheService: CacheService(prefs),
        usnoService: UsnoService(client: _makeUsnoClient()),
        openUvService: _makeOpenUvService(),
      );

      await provider.searchLocation('xyzxyz');
      expect(provider.errorMessage, contains('not found'));
      expect(provider.currentLocation, isNull);
    });
  });

  group('ForecastProvider astro data', () {
    test('cachedAstroData populated after searchLocation', () async {
      final provider = await _makeProvider();
      await provider.searchLocation('Bishop, CA');

      expect(provider.currentLocation!.cachedAstroData, isNotEmpty);
      expect(provider.currentLocation!.cachedAstroData.first, isA<AstroDay>());
    });
  });

  group('ForecastProvider.restoreLocation', () {
    test('undoes a delete, including reopening the current location',
        () async {
      final provider = await _makeProvider();
      await provider.searchLocation('Bishop, CA');
      final loc = provider.currentLocation!;

      provider.deleteLocation(loc.displayName);
      expect(provider.savedLocations, isEmpty);
      expect(provider.currentLocation, isNull);

      provider.restoreLocation(loc, wasCurrent: true);
      expect(provider.savedLocations.single.displayName, loc.displayName);
      expect(provider.currentLocation!.displayName, loc.displayName);
    });
  });

  group('ForecastProvider.selectLocation', () {
    test('loads cached location as current', () async {
      final provider = await _makeProvider();
      await provider.searchLocation('Bishop, CA');

      final saved = provider.savedLocations.first;
      provider.selectLocation(saved);

      expect(provider.currentLocation!.displayName, saved.displayName);
    });
  });
}
