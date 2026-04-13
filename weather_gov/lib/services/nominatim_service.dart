import 'dart:convert';
import 'package:http/http.dart' as http;

class SuggestionResult {
  final String displayName;
  final String shortName;
  final double lat;
  final double lon;

  const SuggestionResult({
    required this.displayName,
    required this.shortName,
    required this.lat,
    required this.lon,
  });
}

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

const _kStateAbbr = {
  'Alabama': 'AL', 'Alaska': 'AK', 'Arizona': 'AZ', 'Arkansas': 'AR',
  'California': 'CA', 'Colorado': 'CO', 'Connecticut': 'CT', 'Delaware': 'DE',
  'Florida': 'FL', 'Georgia': 'GA', 'Hawaii': 'HI', 'Idaho': 'ID',
  'Illinois': 'IL', 'Indiana': 'IN', 'Iowa': 'IA', 'Kansas': 'KS',
  'Kentucky': 'KY', 'Louisiana': 'LA', 'Maine': 'ME', 'Maryland': 'MD',
  'Massachusetts': 'MA', 'Michigan': 'MI', 'Minnesota': 'MN', 'Mississippi': 'MS',
  'Missouri': 'MO', 'Montana': 'MT', 'Nebraska': 'NE', 'Nevada': 'NV',
  'New Hampshire': 'NH', 'New Jersey': 'NJ', 'New Mexico': 'NM', 'New York': 'NY',
  'North Carolina': 'NC', 'North Dakota': 'ND', 'Ohio': 'OH', 'Oklahoma': 'OK',
  'Oregon': 'OR', 'Pennsylvania': 'PA', 'Rhode Island': 'RI', 'South Carolina': 'SC',
  'South Dakota': 'SD', 'Tennessee': 'TN', 'Texas': 'TX', 'Utah': 'UT',
  'Vermont': 'VT', 'Virginia': 'VA', 'Washington': 'WA', 'West Virginia': 'WV',
  'Wisconsin': 'WI', 'Wyoming': 'WY', 'District of Columbia': 'DC',
  'Puerto Rico': 'PR', 'Guam': 'GU', 'U.S. Virgin Islands': 'VI',
  'United States Virgin Islands': 'VI', 'American Samoa': 'AS',
  'Northern Mariana Islands': 'MP', 'Commonwealth of the Northern Mariana Islands': 'MP',
  'United States Minor Outlying Islands': 'UM', 'Palau': 'PW',
  'Federated States of Micronesia': 'FM', 'Marshall Islands': 'MH',
};

class NominatimService {
  final http.Client _client;

  NominatimService({http.Client? client}) : _client = client ?? http.Client();

  /// Returns up to 5 autocomplete suggestions using Photon (OSM-based, prefix-aware).
  Future<List<SuggestionResult>> suggest(String query) async {
    if (query.trim().length < 2) return [];
    try {
      // Photon is built for autocomplete — supports prefix matching natively.
      // bbox covers the continental US + Alaska + Hawaii.
      final uri = Uri.https('photon.komoot.io', '/api/', {
        'q': query,
        'limit': '15',
        'lang': 'en',
        'layer': 'city',
        'bbox': '-180,18,-65,72',
      });
      final response = await _client.get(uri, headers: {
        'User-Agent': 'WeatherGovApp/1.0',
        'Accept': 'application/json',
      });
      if (response.statusCode != 200) return [];
      final body = json.decode(response.body) as Map<String, dynamic>;
      final features = body['features'] as List<dynamic>;
      // Match only against the city name portion (before any comma) so that
      // queries like "New York, New York" still match the city "New York".
      final queryCity = query.split(',').first.trim().toLowerCase();
      final suggestions = <SuggestionResult>[];
      final seen = <String>{};
      for (final f in features) {
        final props = (f as Map<String, dynamic>)['properties'] as Map<String, dynamic>;
        if ((props['countrycode'] as String?) != 'US') continue;
        final name  = props['name']  as String? ?? '';
        final state = props['state'] as String? ?? '';
        if (name.isEmpty || state.isEmpty) continue;
        if (!name.toLowerCase().startsWith(queryCity)) continue;
        final short = '$name, ${_kStateAbbr[state] ?? state}';
        if (!seen.add(short)) continue;
        final coords = (f['geometry'] as Map<String, dynamic>)['coordinates'] as List<dynamic>;
        suggestions.add(SuggestionResult(
          displayName: short,
          shortName: short,
          lat: (coords[1] as num).toDouble(),
          lon: (coords[0] as num).toDouble(),
        ));
        if (suggestions.length >= 5) break;
      }
      return suggestions;
    } catch (_) {
      return [];
    }
  }

  Future<GeocodingResult?> search(String query) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'json',
      'limit': '5',
      'addressdetails': '1',
      'countrycodes': 'us',
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

    // Prefer results whose type is a city/town/village over other place types.
    const cityTypes = {'city', 'town', 'village', 'municipality'};
    final first = results.cast<Map<String, dynamic>>()
        .firstWhere((r) => cityTypes.contains(r['type']), orElse: () => results.first as Map<String, dynamic>);
    final address = first['address'] as Map<String, dynamic>?;
    final lat = double.parse(first['lat'] as String);
    final lon = double.parse(first['lon'] as String);

    // Forward search on a town/city often omits postcode — reverse geocode to get it.
    String? postcode = address?['postcode'] as String?;
    postcode ??= await _reversePostcode(lat, lon);

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
