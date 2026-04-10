import 'dart:convert';
import 'package:http/http.dart' as http;

class GeocodingResult {
  final String displayName;
  final double lat;
  final double lon;
  final String? postcode;

  const GeocodingResult({
    required this.displayName,
    required this.lat,
    required this.lon,
    this.postcode,
  });
}

class NominatimService {
  final http.Client _client;

  NominatimService({http.Client? client}) : _client = client ?? http.Client();

  Future<GeocodingResult?> search(String query) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'json',
      'limit': '1',
      'addressdetails': '1',
    });

    final response = await _client.get(uri, headers: {
      'User-Agent': 'WeatherGovApp/1.0',
      'Accept': 'application/json',
    });

    if (response.statusCode != 200) {
      throw Exception('Nominatim error: ${response.statusCode}');
    }

    final List<dynamic> results = json.decode(response.body) as List<dynamic>;
    if (results.isEmpty) return null;

    final first = results.first as Map<String, dynamic>;
    final address = first['address'] as Map<String, dynamic>?;
    final lat = double.parse(first['lat'] as String);
    final lon = double.parse(first['lon'] as String);

    // Forward search on a town/city often omits postcode — reverse geocode to get it.
    String? postcode = address?['postcode'] as String?;
    if (postcode == null) {
      postcode = await _reversePostcode(lat, lon);
    }

    return GeocodingResult(
      displayName: first['display_name'] as String,
      lat: lat,
      lon: lon,
      postcode: postcode,
    );
  }

  Future<String?> _reversePostcode(double lat, double lon) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': lat.toString(),
        'lon': lon.toString(),
        'format': 'json',
        'addressdetails': '1',
        'zoom': '10', // city-level zoom to get postcode
      });
      final response = await _client.get(uri, headers: {
        'User-Agent': 'WeatherGovApp/1.0',
        'Accept': 'application/json',
      });
      if (response.statusCode != 200) return null;
      final data = json.decode(response.body) as Map<String, dynamic>;
      final address = data['address'] as Map<String, dynamic>?;
      return address?['postcode'] as String?;
    } catch (_) {
      return null;
    }
  }
}
