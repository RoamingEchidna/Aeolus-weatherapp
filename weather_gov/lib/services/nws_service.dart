import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/hourly_period.dart';
import '../models/weather_alert.dart';

class NwsForecastResult {
  final String locationName;
  final List<HourlyPeriod> periods;
  final List<WeatherAlert> alerts;
  /// UTC offset in whole hours for the forecast location (e.g. -7 for PDT).
  final int tzOffsetHours;
  /// IANA timezone name (e.g. "America/Los_Angeles").
  final String timeZone;
  const NwsForecastResult({
    required this.locationName,
    required this.periods,
    required this.alerts,
    required this.tzOffsetHours,
    this.timeZone = '',
  });
}

class NwsUnsupportedLocationException implements Exception {
  final String message;
  const NwsUnsupportedLocationException(this.message);
  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Top-level functions for compute() — must not be closures or instance methods.
// ---------------------------------------------------------------------------

/// Parses an ISO 8601 duration string like PT1H, PT6H, P1DT3H.
Duration _parseDuration(String d) {
  final h = RegExp(r'(\d+)H').firstMatch(d);
  final m = RegExp(r'(\d+)M').firstMatch(d);
  final day = RegExp(r'(\d+)D').firstMatch(d);
  return Duration(
    hours: (int.tryParse(h?.group(1) ?? '') ?? 0) +
        (int.tryParse(day?.group(1) ?? '') ?? 0) * 24,
    minutes: int.tryParse(m?.group(1) ?? '') ?? 0,
  );
}

/// Expands interval-based gridpoint values into a per-UTC-hour map.
/// Each interval value is distributed evenly across its hours.
Map<String, double> _expandToHourly(List<dynamic> values, double Function(dynamic) parse) {
  final result = <String, double>{};
  for (final v in values) {
    final parts = (v['validTime'] as String).split('/');
    final start = DateTime.parse(parts[0]).toUtc();
    final duration = _parseDuration(parts[1]);
    final hours = duration.inHours.clamp(1, 240);
    final raw = parse(v['value']);
    final perHour = raw / hours;
    for (int i = 0; i < hours; i++) {
      result[start.add(Duration(hours: i)).toIso8601String()] = perHour;
    }
  }
  return result;
}

/// Same but last-write-wins (for non-accumulating values like probabilities).
Map<String, double> _expandToHourlyFlat(List<dynamic> values, double Function(dynamic) parse) {
  final result = <String, double>{};
  for (final v in values) {
    final parts = (v['validTime'] as String).split('/');
    final start = DateTime.parse(parts[0]).toUtc();
    final duration = _parseDuration(parts[1]);
    final hours = duration.inHours.clamp(1, 240);
    final raw = parse(v['value']);
    for (int i = 0; i < hours; i++) {
      result[start.add(Duration(hours: i)).toIso8601String()] = raw;
    }
  }
  return result;
}

/// Expands weather type intervals into a per-hour map of type→coverage string.
Map<String, Map<String, String>> _expandWeatherTypes(List<dynamic> values) {
  const relevant = {
    'rain_showers', 'rain', 'freezing_rain', 'freezing_drizzle',
    'ice_pellets', 'sleet', 'snow', 'snow_showers', 'blizzard', 'thunderstorms',
    'fog', 'ice_fog', 'freezing_fog', 'haze', 'smoke',
    'dust', 'sand', 'volcanic_ash', 'water_spouts', 'tornadoes',
  };
  final result = <String, Map<String, String>>{};
  for (final v in values) {
    final parts = (v['validTime'] as String).split('/');
    final start = DateTime.parse(parts[0]).toUtc();
    final duration = _parseDuration(parts[1]);
    final hours = duration.inHours.clamp(1, 240);
    final types = <String, String>{};
    for (final w in (v['value'] as List<dynamic>)) {
      final weather = w['weather'] as String?;
      final coverage = w['coverage'] as String?;
      if (weather != null && relevant.contains(weather) && coverage != null) {
        types[weather] = coverage;
      }
    }
    for (int i = 0; i < hours; i++) {
      result[start.add(Duration(hours: i)).toIso8601String()] = types;
    }
  }
  return result;
}

/// Parsed gridpoint data keyed by UTC hour ISO string.
class _GridpointData {
  final Map<String, double> thunderPct;    // 0–100
  final Map<String, double> rainInchesPerHr;
  final Map<String, double> snowInchesPerHr;
  final Map<String, Map<String, String>> weatherTypes;
  const _GridpointData({
    required this.thunderPct,
    required this.rainInchesPerHr,
    required this.snowInchesPerHr,
    required this.weatherTypes,
  });
}

_GridpointData _parseGridpoint(String body) {
  final data = (json.decode(body) as Map<String, dynamic>)['properties']
      as Map<String, dynamic>;

  final thunderPct = _expandToHourlyFlat(
    (data['probabilityOfThunder'] as Map<String, dynamic>)['values'] as List<dynamic>,
    (v) => (v as num?)?.toDouble() ?? 0.0,
  );

  // quantitativePrecipitation is in mm, convert to inches (1mm = 0.03937in)
  const mmToIn = 0.03937;
  final rainIn = _expandToHourly(
    (data['quantitativePrecipitation'] as Map<String, dynamic>)['values'] as List<dynamic>,
    (v) => ((v as num?)?.toDouble() ?? 0.0) * mmToIn,
  );

  final snowIn = _expandToHourly(
    (data['snowfallAmount'] as Map<String, dynamic>)['values'] as List<dynamic>,
    (v) => ((v as num?)?.toDouble() ?? 0.0) * mmToIn,
  );

  final types = _expandWeatherTypes(
    (data['weather'] as Map<String, dynamic>)['values'] as List<dynamic>,
  );

  return _GridpointData(
    thunderPct: thunderPct,
    rainInchesPerHr: rainIn,
    snowInchesPerHr: snowIn,
    weatherTypes: types,
  );
}

// ---------------------------------------------------------------------------

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

    final pointsJson = json.decode(pointsResp.body) as Map<String, dynamic>;
    final props = pointsJson['properties'] as Map<String, dynamic>;
    final hourlyUrl = props['forecastHourly'] as String;
    final gridDataUrl = props['forecastGridData'] as String;
    final relLoc = (props['relativeLocation']
        as Map<String, dynamic>)['properties'] as Map<String, dynamic>;
    final locationName = '${relLoc['city']}, ${relLoc['state']}';
    final timeZone = (props['timeZone'] as String?) ?? '';

    // Steps 2, 3, 4 fire in parallel
    final alertsUri = Uri.parse('$_base/alerts/active?point=$lat,$lon');
    final responses = await Future.wait([
      _client.get(Uri.parse(hourlyUrl), headers: _headers),
      _client.get(alertsUri, headers: _headers),
      _client.get(Uri.parse(gridDataUrl), headers: _headers),
    ]);

    final hourlyResp  = responses[0];
    final alertsResp  = responses[1];
    final gridResp    = responses[2];

    if (hourlyResp.statusCode != 200) {
      throw Exception('NWS hourly error: ${hourlyResp.statusCode}');
    }

    final hourlyJson = json.decode(hourlyResp.body) as Map<String, dynamic>;
    final periodsJson = hourlyJson['properties']['periods'] as List<dynamic>;

    // Parse gridpoint data on a background isolate to avoid OOM on main thread.
    _GridpointData? gridData;
    if (gridResp.statusCode == 200) {
      try {
        gridData = await compute(_parseGridpoint, gridResp.body);
      } catch (_) {
        // Non-critical — fall back to no gridpoint data.
      }
    }

    final periods = periodsJson.map((e) {
      final p = HourlyPeriod.fromJson(e as Map<String, dynamic>);
      if (gridData == null) return p;
      final key = p.startTime.toUtc().toIso8601String();
      return p.copyWithGrid(
        thunderPct: gridData.thunderPct[key]?.round(),
        rainInchesPerHr: gridData.rainInchesPerHr[key],
        snowInchesPerHr: gridData.snowInchesPerHr[key],
        weatherTypes: gridData.weatherTypes[key],
      );
    }).toList();

    // Extract UTC offset from first period's startTime string.
    int tzOffsetHours = 0;
    if (periodsJson.isNotEmpty) {
      final startTimeStr =
          (periodsJson.first as Map<String, dynamic>)['startTime'] as String?;
      if (startTimeStr != null) {
        final match = RegExp(r'([+-])(\d{2}):\d{2}$').firstMatch(startTimeStr);
        if (match != null) {
          final sign = match.group(1) == '-' ? -1 : 1;
          tzOffsetHours = sign * int.parse(match.group(2)!);
        }
      }
    }

    // Alerts are non-critical — suppress errors.
    List<WeatherAlert> alerts = [];
    if (alertsResp.statusCode == 200) {
      final alertsJson = json.decode(alertsResp.body) as Map<String, dynamic>;
      alerts = (alertsJson['features'] as List<dynamic>)
          .map((e) => WeatherAlert.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return NwsForecastResult(
      locationName: locationName,
      periods: periods,
      alerts: alerts,
      tzOffsetHours: tzOffsetHours,
      timeZone: timeZone,
    );
  }
}
