import 'dart:convert';
import 'package:http/http.dart' as http;

class GeocodingResult {
  final String displayName;
  final double lat;
  final double lon;

  const GeocodingResult({
    required this.displayName,
    required this.lat,
    required this.lon,
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
    return GeocodingResult(
      displayName: first['display_name'] as String,
      lat: double.parse(first['lat'] as String),
      lon: double.parse(first['lon'] as String),
    );
  }
}
