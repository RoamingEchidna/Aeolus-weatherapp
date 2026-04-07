import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/hourly_period.dart';
import '../models/weather_alert.dart';

class NwsForecastResult {
  final String locationName;
  final List<HourlyPeriod> periods;
  final List<WeatherAlert> alerts;

  const NwsForecastResult({
    required this.locationName,
    required this.periods,
    required this.alerts,
  });
}

class NwsUnsupportedLocationException implements Exception {
  final String message;
  const NwsUnsupportedLocationException(this.message);
  @override
  String toString() => message;
}

class NwsService {
  final http.Client _client;
  static const _base = 'https://api.weather.gov';
  static const _headers = {
    'User-Agent': 'WeatherGovApp/1.0',
    'Accept': 'application/geo+json',
  };

  NwsService({http.Client? client}) : _client = client ?? http.Client();

  Future<NwsForecastResult> fetchForecast(double lat, double lon) async {
    // Step 1: resolve grid point
    final pointsUri = Uri.parse(
        '$_base/points/${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}');
    final pointsResp = await _client.get(pointsUri, headers: _headers);

    if (pointsResp.statusCode == 404) {
      throw const NwsUnsupportedLocationException(
          'Location not supported by NWS');
    }
    if (pointsResp.statusCode != 200) {
      throw Exception('NWS points error: ${pointsResp.statusCode}');
    }

    final pointsJson =
        json.decode(pointsResp.body) as Map<String, dynamic>;
    final props = pointsJson['properties'] as Map<String, dynamic>;
    final hourlyUrl = props['forecastHourly'] as String;
    final relLoc = (props['relativeLocation']
        as Map<String, dynamic>)['properties'] as Map<String, dynamic>;
    final locationName = '${relLoc['city']}, ${relLoc['state']}';

    // Steps 2 & 3 fire in parallel
    final alertsUri = Uri.parse('$_base/alerts/active?point=$lat,$lon');
    final results = await Future.wait([
      _client.get(Uri.parse(hourlyUrl), headers: _headers),
      _client.get(alertsUri, headers: _headers),
    ]);

    final hourlyResp = results[0];
    final alertsResp = results[1];

    if (hourlyResp.statusCode != 200) {
      throw Exception('NWS hourly error: ${hourlyResp.statusCode}');
    }

    final hourlyJson =
        json.decode(hourlyResp.body) as Map<String, dynamic>;
    final periodsJson =
        hourlyJson['properties']['periods'] as List<dynamic>;
    final periods = periodsJson
        .map((e) => HourlyPeriod.fromJson(e as Map<String, dynamic>))
        .toList();

    // Alerts are non-critical — suppress errors
    List<WeatherAlert> alerts = [];
    if (alertsResp.statusCode == 200) {
      final alertsJson =
          json.decode(alertsResp.body) as Map<String, dynamic>;
      alerts = (alertsJson['features'] as List<dynamic>)
          .map((e) => WeatherAlert.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return NwsForecastResult(
      locationName: locationName,
      periods: periods,
      alerts: alerts,
    );
  }
}
