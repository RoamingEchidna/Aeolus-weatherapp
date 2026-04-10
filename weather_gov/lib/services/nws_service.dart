import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/hourly_period.dart';
import '../models/weather_alert.dart';

class NwsForecastResult {
  final String locationName;
  final List<HourlyPeriod> periods;
  final List<WeatherAlert> alerts;
  /// UTC offset in whole hours for the forecast location (e.g. -7 for PDT).
  final int tzOffsetHours;
  const NwsForecastResult({
    required this.locationName,
    required this.periods,
    required this.alerts,
    required this.tzOffsetHours,
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
    final coreResults = await Future.wait([
      _client.get(Uri.parse(hourlyUrl), headers: _headers),
      _client.get(alertsUri, headers: _headers),
    ]);

    final hourlyResp = coreResults[0];
    final alertsResp = coreResults[1];

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

    // Extract the location's UTC offset from the first period's startTime string
    // (e.g. "2024-04-09T14:00:00-07:00" → -7). Falls back to 0 if unparseable.
    int tzOffsetHours = 0;
    if (periodsJson.isNotEmpty) {
      final startTimeStr =
          (periodsJson.first as Map<String, dynamic>)['startTime'] as String?;
      if (startTimeStr != null) {
        final match =
            RegExp(r'([+-])(\d{2}):\d{2}$').firstMatch(startTimeStr);
        if (match != null) {
          final sign = match.group(1) == '-' ? -1 : 1;
          tzOffsetHours = sign * int.parse(match.group(2)!);
        }
      }
    }

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
      tzOffsetHours: tzOffsetHours,
    );
  }
}
