import 'hourly_period.dart';
import 'weather_alert.dart';

class SavedLocation {
  final String displayName;
  final double lat;
  final double lon;
  final DateTime lastAccessed;
  final List<HourlyPeriod> cachedForecast;
  final List<WeatherAlert> cachedAlerts;
  final DateTime cacheTimestamp;

  const SavedLocation({
    required this.displayName,
    required this.lat,
    required this.lon,
    required this.lastAccessed,
    required this.cachedForecast,
    required this.cachedAlerts,
    required this.cacheTimestamp,
  });

  SavedLocation copyWith({
    String? displayName,
    double? lat,
    double? lon,
    DateTime? lastAccessed,
    List<HourlyPeriod>? cachedForecast,
    List<WeatherAlert>? cachedAlerts,
    DateTime? cacheTimestamp,
  }) {
    return SavedLocation(
      displayName: displayName ?? this.displayName,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      lastAccessed: lastAccessed ?? this.lastAccessed,
      cachedForecast: cachedForecast ?? this.cachedForecast,
      cachedAlerts: cachedAlerts ?? this.cachedAlerts,
      cacheTimestamp: cacheTimestamp ?? this.cacheTimestamp,
    );
  }

  factory SavedLocation.fromJson(Map<String, dynamic> json) {
    return SavedLocation(
      displayName: json['displayName'] as String,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      lastAccessed: DateTime.parse(json['lastAccessed'] as String),
      cachedForecast: (json['cachedForecast'] as List<dynamic>)
          .map((e) => HourlyPeriod.fromStoredJson(e as Map<String, dynamic>))
          .toList(),
      cachedAlerts: (json['cachedAlerts'] as List<dynamic>)
          .map((e) => WeatherAlert.fromStoredJson(e as Map<String, dynamic>))
          .toList(),
      cacheTimestamp: DateTime.parse(json['cacheTimestamp'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'lat': lat,
        'lon': lon,
        'lastAccessed': lastAccessed.toIso8601String(),
        'cachedForecast': cachedForecast.map((p) => p.toJson()).toList(),
        'cachedAlerts': cachedAlerts.map((a) => a.toJson()).toList(),
        'cacheTimestamp': cacheTimestamp.toIso8601String(),
      };
}
