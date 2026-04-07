import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:weather_gov/services/nominatim_service.dart';

void main() {
  group('NominatimService.search', () {
    test('returns lat/lon and display name on success', () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'nominatim.openstreetmap.org');
        expect(request.url.queryParameters['q'], 'Bishop, CA');
        expect(request.headers['User-Agent'], contains('WeatherGovApp'));
        return http.Response('''
          [{"display_name":"Bishop, Inyo County, California, United States",
            "lat":"37.3635",
            "lon":"-118.3949"}]
        ''', 200);
      });

      final service = NominatimService(client: client);
      final result = await service.search('Bishop, CA');

      expect(result, isNotNull);
      expect(result!.displayName, contains('Bishop'));
      expect(result.lat, closeTo(37.3635, 0.001));
      expect(result.lon, closeTo(-118.3949, 0.001));
    });

    test('returns null when no results found', () async {
      final client = MockClient((_) async => http.Response('[]', 200));
      final service = NominatimService(client: client);
      final result = await service.search('xyzxyzxyz');
      expect(result, isNull);
    });

    test('throws on HTTP error', () async {
      final client = MockClient((_) async => http.Response('error', 500));
      final service = NominatimService(client: client);
      expect(() => service.search('Bishop'), throwsException);
    });
  });
}
